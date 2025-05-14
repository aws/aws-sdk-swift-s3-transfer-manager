//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import class Foundation.OutputStream
import enum Smithy.ByteStream
import struct Foundation.Data

public extension S3TransferManager {
    /// Downloads a single object from S3 to the`OutputStream` configured in the input.
    ///
    /// Returns a `Task` immediately after function call; download is handled in the background using asynchronous child tasks.
    /// If the `Task` returned by the function gets cancelled, all child tasks also get cancelled automatically.
    ///
    /// - Parameters:
    ///   - input: An instance of `DownloadObjectInput`, the synthetic input type specific to this operation of `S3TransferManager`.
    /// - Returns: An asynchronous `Task<DownloadObjectOutput, Error>` that can be optionally waited on or cancelled as needed.
    func downloadObject(input: DownloadObjectInput) throws -> Task<DownloadObjectOutput, Error> {
        return Task {
            input.transferListeners.forEach { $0.onTransferInitiated(
                input: input,
                snapshot: SingleObjectTransferProgressSnapshot(transferredBytes: 0)
            )}
            defer { input.outputStream.close() }

            let progressTracker = ObjectTransferProgressTracker()
            let s3 = config.s3Client

            do {
                return try await determineAndExecuteDownloadStrategy(input, progressTracker, s3)
            } catch {
                let snapshot = SingleObjectTransferProgressSnapshot(
                    transferredBytes: await progressTracker.transferredBytes
                )
                input.transferListeners.forEach { $0.onTransferFailed(
                    input: input,
                    snapshot: snapshot,
                    error: error
                )}
                throw error
            }
        }
    }

    private func determineAndExecuteDownloadStrategy(
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client
    ) async throws -> DownloadObjectOutput {
        let partNumber = input.getObjectInput.partNumber
        // Case 0: Specific part number was given. Do a single part GET.
        if partNumber != nil {
            return try await singleGET(input, progressTracker, s3)
        }
        let downloadType = config.multipartDownloadType
        let range = input.getObjectInput.range

        // Case 1: Config is part GET with range given. Fallback to single GET with given range.
        if range != nil && downloadType == .part {
            return try await singleGET(input, progressTracker, s3)
        }

        // Case 2: Config is part GET with no range given. Do a multipart GET with MPU parts.
        if downloadType == .part && range == nil {
            return try await multiPartGET(input, progressTracker, s3)
        }

        // Case 3: Config is range GET with range given.
        if let range, downloadType == .range {
            let (start, end) = try parseBytesRangeHeader(headerStr: range)
            if let end {
                // Case 3A: Provided range is in "bytes=<start>-<end>" format.
                // End is inclusive so must add 1 to get object size.
                // E.g., "bytes=2-10" is a 9 byte range (byte 2 to byte 9, inclusive). 10 - 2 + 1 = 9.
                let objectSize = end - start + 1

                // If one range GET is enough to get everything, do a single range GET and return.
                if objectSize <= config.targetPartSizeBytes {
                    return try await singleGET(input, progressTracker, s3)
                }

                // Otherwise, get the entire object (start - provided_end) concurrently.
                return try await multiRangeGET(input, progressTracker, s3, start, end, objectSize)
            } else {
                // Case 3B: Provided range is in "bytes=<start>-" format.
                // Get the entire object (start - end_of_entire_object) concurrently with range GET.
                return try await multiRangeGET(input, progressTracker, s3, start)
            }
        }

        // Case 4: Config is range GET with no range given.
        if downloadType == .range && range == nil {
            // Get the entire object (0 - end_of_entire_object) concurrently with range GET.
            return try await multiRangeGET(input, progressTracker, s3, 0)
        }

        // Cases 0 to 4 above covers all possible cases.
        // Unreachable statement; added to quiet compiler.
        throw S3TMDownloadObjectError.invalidDownloadConfiguration
    }

    // Handles single GET cases: Case 0, 1, and when one range GET is enough.
    private func singleGET(
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client
    ) async throws -> DownloadObjectOutput {
        let singleGetOutput = try await performSingleGET(input, input.getObjectInput, progressTracker, s3)
        return await publishTransferCompleteAndReturnOutput(singleGetOutput, input, progressTracker)
    }

    // Helper that makes a single GetObject request; used by all cases.
    private func performSingleGET(
        _ downloadObjectInput: DownloadObjectInput,
        _ getObjectInput: GetObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client
    ) async throws -> GetObjectOutput {
        let bucketName = getObjectInput.bucket!

        let (getObjectOutput, outputData) = try await withBucketPermission(bucketName: bucketName) {
            try Task.checkCancellation()
            let getObjectOutput = try await s3.getObject(input: getObjectInput)
            // Write returned data to user-provided output stream & return.
            guard let outputData = try await getObjectOutput.body?.readData() else {
                throw S3TMDownloadObjectError.failedToReadResponseBody
            }
            return (getObjectOutput, outputData)
        }

        try await writeData(outputData, to: downloadObjectInput.outputStream, downloadObjectInput, progressTracker)
        return getObjectOutput
    }

    // Handles multipart GET for Case 2.
    private func multiPartGET(
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client
    ) async throws -> DownloadObjectOutput {
        let triageGETInput = input.copyGetObjectInputWithPartNumberOrRange(partNumber: 1)
        let triageGETOutput = try await performSingleGET(input, triageGETInput, progressTracker, s3)

        // Return if there's no more parts.
        guard let totalParts = triageGETOutput.partsCount, totalParts > 1 else {
            return await publishTransferCompleteAndReturnOutput(triageGETOutput, input, progressTracker)
        }

        // Otherwise, fetch all remaining parts and write to the output stream. Then return.
        try await getRemainingObjectWithPartGETs(input, progressTracker, s3, totalParts)
        return await publishTransferCompleteAndReturnOutput(triageGETOutput, input, progressTracker)
    }

    private func getRemainingObjectWithPartGETs(
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client,
        _ totalParts: Int
    ) async throws {
        let bucketName = input.getObjectInput.bucket!
        // Size of batch is same as the task limit per bucket.
        let batchSize = concurrentTaskLimitPerBucket

        // Process all parts in batches.
        for batchStart in stride(from: 2, to: totalParts + 1, by: batchSize) {
            let batchEnd = min(batchStart + batchSize - 1, totalParts)

            try await withThrowingTaskGroup(of: (Int, ByteStream).self) { group in
                // Add child task for each part GET in current batch.
                for partNumber in batchStart...batchEnd {
                    group.addTask { // Each child task returns (part_number, stream) tuple.
                        return try await self.withBucketPermission(bucketName: bucketName) {
                            try Task.checkCancellation()
                            let partGetObjectInput = input.copyGetObjectInputWithPartNumberOrRange(
                                partNumber: partNumber
                            )
                            let partGetObjectOutput = try await s3.getObject(input: partGetObjectInput)
                            return (partNumber, partGetObjectOutput.body!)
                        }
                    }
                }

                // Write results of part GETs in current batch to `input.outputStream` in order.
                try await writeBatch(group, to: input.outputStream, batchStart, input, progressTracker)
            }
        }
    }

    // Handles range GET for Case 3A, 3B, and 4.
    private func multiRangeGET(
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client,
        _ startByte: Int,
        _ endByte: Int? = nil, // Known only for "bytes=<start>-<end>".
        _ knownObjectSize: Int? = nil // Known only for "bytes=<start>-<end>".
    ) async throws -> DownloadObjectOutput {
        // End is inclusive, so must subtract 1 to get target byte amount.
        // E.g., if start is 2nd byte, to get 8 bytes, range becomes "bytes=2-9"; 2 + 8 - 1 = 9.
        let triageGETInput = input.copyGetObjectInputWithPartNumberOrRange(
            range: "bytes=\(startByte)-\(startByte + config.targetPartSizeBytes - 1)"
        )
        let triageGETOutput = try await performSingleGET(input, triageGETInput, progressTracker, s3)

        let objectSize = try determineObjectSize(triageGETOutput, knownObjectSize, startByte)

        // Return if one range GET was enough to get everything.
        if objectSize <= config.targetPartSizeBytes {
            return await publishTransferCompleteAndReturnOutput(triageGETOutput, input, progressTracker)
        }

        // Otherwise, fetch all remaining segments and write to the output stream.
        // Start byte is adjusted to 2nd segment since we already did first range GET above.
        let start = startByte + config.targetPartSizeBytes
        try await getRemainingObjectWithRangedGETs(endByte, input, objectSize, progressTracker, s3, start)

        return await publishTransferCompleteAndReturnOutput(triageGETOutput, input, progressTracker)
    }

    private func determineObjectSize(
        _ getObjectOutput: GetObjectOutput,
        _ knownObjectSize: Int?,
        _ startByte: Int
    ) throws -> Int {
        if let knownObjectSize {
            // Use partial object size from <start>-<end> if present.
            return knownObjectSize
        } else {
            // Determine full object size from first output's Content-Range header.
            guard let contentRange = getObjectOutput.contentRange else {
                throw S3TMDownloadObjectError.failedToDetermineObjectSize
            }
            // This is the start-byte-adjusted object size.
            return try getObjectSizeFromContentRangeHeader(headerStr: contentRange) - startByte
        }
    }

    private func publishTransferCompleteAndReturnOutput(
        _ firstGetObjectOutput: GetObjectOutput,
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker
    ) async -> DownloadObjectOutput {
        let downloadObjectOutput = DownloadObjectOutput(getObjectOutput: firstGetObjectOutput)
        let transferredBytes = await progressTracker.transferredBytes
        input.transferListeners.forEach { $0.onTransferComplete(
            input: input,
            output: downloadObjectOutput,
            snapshot: SingleObjectTransferProgressSnapshot(transferredBytes: transferredBytes)
        )}
        return downloadObjectOutput
    }

    private func getRemainingObjectWithRangedGETs(
        _ endByte: Int? = nil, // Known only for "bytes=<start>-<end>".
        _ input: DownloadObjectInput,
        _ objectSize: Int,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client,
        _ startByte: Int
    ) async throws {
        /*
            Must subtract 1 if there was no remainder, since we already sent a "triage" request that doubled as getting the object size. E.g., say `objectSize` is 100 and part size is 10. We have 90 more bytes to fetch at this point. 100 / 10 = 10. Subtract 1 to get 9, which is the remaining number of requests we need to make. Now, say object size is 103 and part size is 10. We have 93 more bytes to fetch. We need to make 10 requests to get all 93 bytes (9 x 10 byte requests, and 10th request with 3 bytes). 100 / 10 = 10. So we don't subtract 1 from it if there's a remainder.
         */
        let numRequests = (objectSize / config.targetPartSizeBytes)
        - (objectSize % config.targetPartSizeBytes == 0 ? 1 : 0)
        let bucketName = input.getObjectInput.bucket!

        // Size of batch is same as the task limit per bucket.
        let batchSize = concurrentTaskLimitPerBucket
        for batchStart in stride(from: 0, to: numRequests, by: batchSize) {
            let batchEnd = min(batchStart + batchSize - 1, numRequests - 1)

            try await withThrowingTaskGroup(of: (Int, ByteStream).self) { group in
                // Add child task for each range GET in current batch.
                for numRequest in batchStart...batchEnd {
                    let rangeGetObjectInput = constructRangetGetObjectInput(
                        endByte, input, numRequest, numRequests, startByte
                    )
                    group.addTask { // Each child task returns (request_number, stream) tuple.
                        return try await self.withBucketPermission(bucketName: bucketName) {
                            try Task.checkCancellation()
                            let rangeGetObjectOutput = try await s3.getObject(input: rangeGetObjectInput)
                            return (numRequest, rangeGetObjectOutput.body!)
                        }
                    }
                }

                // Write results of range GETs in current batch to `input.outputStream` in order.
                try await writeBatch(group, to: input.outputStream, batchStart, input, progressTracker)
            }
        }
    }

    private func constructRangetGetObjectInput(
        _ endByte: Int?,
        _ input: DownloadObjectInput,
        _ numRequest: Int,
        _ numRequests: Int,
        _ startByte: Int
    ) -> GetObjectInput {
        let subRangeStart = startByte + (numRequest * config.targetPartSizeBytes)
        // End byte is inclusive, so must subtract 1 to get target byte amount.
        // If `subRangeEnd` exceeds object size for last segment, bc S3 automatically handles that (returns only up to available bytes).
        var subRangeEnd = subRangeStart + config.targetPartSizeBytes - 1
        // If it's the last request, we must use `end` if it's non-nil.
        if let endByte, numRequest + 1 == numRequests { // + 1 bc numRequest is 0-indexed.
            subRangeEnd = endByte
        }
        return input.copyGetObjectInputWithPartNumberOrRange(
            range: "bytes=\(subRangeStart)-\(subRangeEnd)"
        )
    }

    internal func writeData(
        _ data: Data,
        to outputStream: OutputStream,
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker
    ) async throws {
        if outputStream.streamStatus == .notOpen { outputStream.open() }
        // Write to output stream.
        let bytesWritten = data.withUnsafeBytes { bufferPointer -> Int in
            guard let baseAddress = bufferPointer.baseAddress else { return -1 }
            return outputStream.write(baseAddress.assumingMemoryBound(to: UInt8.self), maxLength: bufferPointer.count)
        }
        if bytesWritten < 0 { throw S3TMDownloadObjectError.failedToWriteToOutputStream }
        let transferredBytes = await progressTracker.addBytes(bytesWritten)
        input.transferListeners.forEach { $0.onBytesTransferred(
            input: input,
            snapshot: SingleObjectTransferProgressSnapshot(transferredBytes: transferredBytes)
        )}
    }

    internal func writeByteStream(
        _ byteStream: ByteStream,
        to outputStream: OutputStream,
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker
    ) async throws {
        guard let data = try await byteStream.readData() else {
            throw S3TMDownloadObjectError.failedToReadResponseBody
        }
        try await writeData(
            data,
            to: outputStream,
            input,
            progressTracker
        )
    }

    private func writeBatch(
        _ group: ThrowingTaskGroup<(Int, ByteStream), any Error>,
        to outputStream: OutputStream,
        _ batchStart: Int,
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker
    ) async throws {
        // Temporary buffer used to ensure correct ordering of data when writing to the output stream.
        var buffer = [Int: ByteStream]()

        var nextBodyToProcess = batchStart
        for try await (index, body) in group {
            buffer[index] = body
            while let body = buffer[nextBodyToProcess] {
                try await writeByteStream(body, to: input.outputStream, input, progressTracker)
                // Discard stream after it's written to output stream.
                buffer.removeValue(forKey: nextBodyToProcess)
                nextBodyToProcess += 1
            }
        }
    }

    internal func parseBytesRangeHeader(headerStr: String) throws -> (start: Int, end: Int?) {
        guard headerStr.hasPrefix("bytes=") else {
            throw S3TMDownloadObjectError.invalidRangeFormat("Range must begin with \"bytes=\".")
        }

        let range = headerStr.dropFirst(6)
        guard !range.hasPrefix("-") else {
            throw S3TMDownloadObjectError.invalidRangeFormat("Suffix range is not supported.")
        }

        let parts = range.split(separator: "-", maxSplits: 1)
        guard parts.count <= 2 else {
            throw S3TMDownloadObjectError.invalidRangeFormat(
                "Multi-range value in Range header is not supported by S3."
            )
        }

        guard let start = Int(parts[0]) else {
            throw S3TMDownloadObjectError.invalidRangeFormat("Range start couldn't be parsed to Int!")
        }

        if parts.count == 1 { // bytes=<start>-
            return (start, nil)
        }

        guard let end = Int(parts[1]) else { // bytes=<start>-<end>
            throw S3TMDownloadObjectError.invalidRangeFormat("Range end couldn't be parsed to Int!")
        }

        return (start, end)
    }

    internal func getObjectSizeFromContentRangeHeader(headerStr: String) throws -> Int {
        let parts = headerStr.split(separator: "/")
        guard let sizeStr = parts.last, let size = Int(sizeStr) else {
            throw S3TMDownloadObjectError.failedToDetermineObjectSize
        }
        return size
    }
}

/// A non-exhaustive list of errors that can be thrown by the `downloadObject` operation of `S3TransferManager`.
public enum S3TMDownloadObjectError: Error {
    case failedToReadResponseBody
    case failedToDetermineObjectSize
    case invalidDownloadConfiguration
    case failedToWriteToOutputStream
    case invalidRangeFormat(String)
}
