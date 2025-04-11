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
            onTransferInitiated(
                input.transferListeners,
                input,
                SingleObjectTransferProgressSnapshot(transferredBytes: 0)
            )
            defer { input.outputStream.close() }

            let s3 = config.s3Client
            let partNumber = input.getObjectInput.partNumber

            // The actor used to keep track of the number of downloaded bytes.
            let progressTracker = ObjectTransferProgressTracker()

            // Helper function used by single GET cases.
            func returnResultOfPerformSingleGET() async throws -> DownloadObjectOutput {
                let singleGetOutput = try await performSingleGET(
                    s3,
                    input.getObjectInput,
                    input,
                    progressTracker
                )

                let transferredBytes = await progressTracker.transferredBytes
                let downloadObjectOutput = DownloadObjectOutput(getObjectOutput: singleGetOutput)

                // `downloadObject` call finished successfully. Return output.
                onTransferComplete(
                    input.transferListeners,
                    input,
                    downloadObjectOutput,
                    SingleObjectTransferProgressSnapshot(transferredBytes: transferredBytes)
                )
                return downloadObjectOutput
            }

            do {
                // Case 0: Specific part number was given. Do a single part GET.
                if partNumber != nil {
                    return try await returnResultOfPerformSingleGET()
                }

                let downloadType = config.multipartDownloadType
                let range = input.getObjectInput.range

                // Case 1: Config is part GET with range given. Fallback to single range GET.
                if range != nil && downloadType == .part {
                    return try await returnResultOfPerformSingleGET()
                }

                // Case 2: Config is part GET with no range given. Do a multipart GET with MPU parts.
                if downloadType == .part && range == nil {
                    return try await performMultipartGET(s3: s3, input: input, progressTracker: progressTracker)
                }

                // Case 3: Config is range GET with range given.
                if let range, downloadType == .range {
                    let (start, end) = try parseBytesRange(str: range)
                    if let end { // Case 3A: Provided range is in "bytes=<start>-<end>" format.
                        // End is inclusive so must add 1 to get object size.
                        // E.g., "bytes=2-10" is a 9 byte range (byte 2 to byte 9, inclusive). 10 - 2 + 1 = 9.
                        let objectSize = end - start + 1

                        // If one range GET is enough to get everything, do a single range GET and return.
                        if objectSize <= config.targetPartSizeBytes {
                            return try await returnResultOfPerformSingleGET()
                        }

                        // Otherwise, get the entire object (start - provided_end) concurrently.
                        return try await performRangeGET(
                            startByte: start,
                            endByte: end,
                            knownObjectSize: objectSize,
                            s3: s3,
                            input: input,
                            progressTracker: progressTracker
                        )
                    } else { // Case 3B: Provided range is in "bytes=<start>-" format.
                        // Get the entire object (start - end_of_entire_object) concurrently with range GET.
                        return try await performRangeGET(
                            startByte: start,
                            s3: s3,
                            input: input,
                            progressTracker: progressTracker
                        )
                    }
                }

                // Case 4: Config is range GET with no range given.
                if downloadType == .range && range == nil {
                    // Get the entire object (0 - end_of_entire_object) concurrently with range GET.
                    return try await performRangeGET(
                        startByte: 0,
                        s3: s3,
                        input: input,
                        progressTracker: progressTracker
                    )
                }

                // Cases 0 to 4 above covers all possible cases.
                // Unreachable statement; added to quiet compiler.
                throw S3TMDownloadObjectError.invalidDownloadConfiguration
            } catch {
                onTransferFailed(
                    input.transferListeners,
                    input,
                    SingleObjectTransferProgressSnapshot(transferredBytes: await progressTracker.transferredBytes),
                    error
                )
                throw error
            }
        }
    }

    private func performSingleGET(
        _ s3: S3Client,
        _ getObjectInput: GetObjectInput,
        _ downloadObjectInput: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker
    ) async throws -> GetObjectOutput {
        defer {
            Task {
                await taskCompleted(bucketName)
            }
        }
        let bucketName = getObjectInput.bucket!
        await waitForPermission(bucketName)

        let getObjectOutput = try await s3.getObject(input: getObjectInput)
        // Write returned data to user-provided output stream & return.
        guard let outputData = try await getObjectOutput.body?.readData() else {
            throw S3TMDownloadObjectError.failedToReadResponseBody
        }
        try await writeData(
            outputData,
            to: downloadObjectInput.outputStream,
            downloadObjectInput,
            progressTracker
        )
        return getObjectOutput
    }

    // Synchronously writes data to output stream.
    internal func writeData(
        _ data: Data,
        to outputStream: OutputStream,
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker
    ) async throws {
        if outputStream.streamStatus == .notOpen {
            outputStream.open()
        }
        var tempBuffer = [UInt8](repeating: 0, count: data.count)
        // Copy data to temporary buffer.
        data.copyBytes(to: &tempBuffer, count: data.count)
        // Write buffer to output stream.
        let bytesWritten = outputStream.write(&tempBuffer, maxLength: tempBuffer.count)
        if bytesWritten < 0 {
            throw S3TMDownloadObjectError.failedToWriteToOutputStream
        }
        let transferredBytes = await progressTracker.addBytes(bytesWritten)
        onBytesTransferred(
            input.transferListeners,
            input,
            SingleObjectTransferProgressSnapshot(transferredBytes: transferredBytes)
        )
    }

    // Handles multipart GET for Case 2.
    private func performMultipartGET(
        s3: S3Client,
        input: DownloadObjectInput,
        progressTracker: ObjectTransferProgressTracker
    ) async throws -> DownloadObjectOutput {
        let firstGetObjectInput = input.copyGetObjectInputWithPartNumberOrRange(partNumber: 1)
        let firstGetObjectOutput = try await performSingleGET(
            s3,
            firstGetObjectInput,
            input,
            progressTracker
        )

        // Return if there's no more parts.
        guard let totalParts = firstGetObjectOutput.partsCount, totalParts > 1 else {
            // `downloadObject` call finished successfully.
            let downloadObjectOutput = DownloadObjectOutput(getObjectOutput: firstGetObjectOutput)
            onTransferComplete(
                input.transferListeners,
                input,
                downloadObjectOutput,
                SingleObjectTransferProgressSnapshot(transferredBytes: await progressTracker.transferredBytes)
            )
            return downloadObjectOutput
        }

        // Otherwise, fetch all remaining parts and write to the output stream.
        try await concurrentlyFetchPartGETByteStreamsAndWriteToOutputStream(
            s3: s3,
            input: input,
            totalParts: totalParts,
            progressTracker: progressTracker
        )

        // `downloadObject` call finished successfully.
        // Return the first `getObject` call's output wrapped in `DownloadObjectOutput`.
        // This behavior aligns with S3 multipart download behavior in Java.
        let downloadObjectOutput = DownloadObjectOutput(getObjectOutput: firstGetObjectOutput)
        onTransferComplete(
            input.transferListeners,
            input,
            downloadObjectOutput,
            SingleObjectTransferProgressSnapshot(transferredBytes: await progressTracker.transferredBytes)
        )
        return downloadObjectOutput
    }

    // Gets all parts of an S3 object starting at second part and writes them to the output stream.
    private func concurrentlyFetchPartGETByteStreamsAndWriteToOutputStream(
        s3: S3Client,
        input: DownloadObjectInput,
        totalParts: Int,
        progressTracker: ObjectTransferProgressTracker
    ) async throws {
        // Size of batch is same as the task limit per bucket.
        let batchSize = concurrentTaskLimitPerBucket
        // Starting part number.
        var currentBatchStart = 2

        // Loop until all parts are retrieved and processed in batches.
        while currentBatchStart <= totalParts {
            // Temporary buffer used to ensure correct ordering of data when writing to the output stream.
            var buffer = [Int: ByteStream]()

            let currentBatchEnd = min(currentBatchStart + batchSize - 1, totalParts)
            try await withThrowingTaskGroup(
                // Each child task returns (part_number, stream) tuple.
                of: (partNumber: Int, byteStream: ByteStream).self
            ) { group in
                // Ensures taskCompleted() is called for all child tasks.
                defer {
                    Task {
                        for _ in 0..<(await taskCounter.pendingCompletionSignal) {
                            await self.taskCompleted(bucketName)
                        }
                    }
                }

                let taskCounter = DownloadTaskCounter()
                let bucketName = input.getObjectInput.bucket!

                // Add child task for each part GET in current batch.
                for partNumber in currentBatchStart...currentBatchEnd {
                    group.addTask {
                        await taskCounter.incrementStart()
                        await self.waitForPermission(bucketName)
                        do {
                            try Task.checkCancellation()
                            let partGetObjectInput = input.copyGetObjectInputWithPartNumberOrRange(
                                partNumber: partNumber
                            )
                            let partGetObjectOutput = try await s3.getObject(input: partGetObjectInput)
                            // await self.taskCompleted is NOT called in this do-block (only in the matching catch block).
                            // That's because connection is alive until everything is read from the body.
                            return (partNumber, partGetObjectOutput.body!)
                        } catch {
                            await self.taskCompleted(bucketName)
                            await taskCounter.incrementCompletion()
                            throw error
                        }
                    }
                }

                // Write results of part GETs in current batch to `input.outputStream` in order.
                var nextPartToProcess = currentBatchStart
                for try await (partNumber, body) in group {
                    buffer[partNumber] = body
                    while let body = buffer[nextPartToProcess] {
                        try await writeByteStream(
                            body,
                            to: input.outputStream,
                            input,
                            progressTracker
                        )
                        // Call taskCompleted() now that we read the entire part and connection is gonna get cleaned up.
                        await taskCompleted(bucketName)
                        await taskCounter.incrementCompletion()
                        // Discard stream after it's written to output stream.
                        buffer.removeValue(forKey: nextPartToProcess)
                        nextPartToProcess += 1
                    }
                }
            }
            // Update batch start to next batch start.
            currentBatchStart = currentBatchEnd + 1
        }
    }

    // Handles range GET for Case 3A, 3B, and 4.
    private func performRangeGET(
        startByte: Int,
        endByte: Int? = nil, // Known only for "bytes=<start>-<end>".
        knownObjectSize: Int? = nil, // Known only for "bytes=<start>-<end>".
        s3: S3Client,
        input: DownloadObjectInput,
        progressTracker: ObjectTransferProgressTracker
    ) async throws -> DownloadObjectOutput {
        // End is inclusive, so must subtract 1 to get target amount.
        // E.g., if start is 2nd byte, to get 8 bytes, range becomes "bytes=2-9"; 2 + 8 - 1 = 9.
        let firstRangeGetObjectInput = input.copyGetObjectInputWithPartNumberOrRange(
            range: "bytes=\(startByte)-\(startByte + config.targetPartSizeBytes - 1)"
        )
        let firstRangeGetObjectOutput = try await performSingleGET(
            s3,
            firstRangeGetObjectInput,
            input,
            progressTracker
        )

        let objectSize: Int
        if let knownObjectSize {
            // Use partial object size from <start>-<end> if present.
            objectSize = knownObjectSize
        } else {
            // Determine full object size from first output's Content-Range header.
            guard let contentRange = firstRangeGetObjectOutput.contentRange else {
                throw S3TMDownloadObjectError.failedToDetermineObjectSize
            }
            // This is the start-byte-adjusted object size.
            objectSize = try getSizeFromContentRangeString(str: contentRange) - startByte
        }

        // Return if one range GET was enough to get everything.
        if objectSize <= config.targetPartSizeBytes {
            // downloadObject call finished successfully. Return output of first range GET.
            let downloadObjectOutput = DownloadObjectOutput(getObjectOutput: firstRangeGetObjectOutput)
            onTransferComplete(
                input.transferListeners,
                input,
                downloadObjectOutput,
                SingleObjectTransferProgressSnapshot(transferredBytes: await progressTracker.transferredBytes)
            )
            return downloadObjectOutput
        }

        // Otherwise, fetch all remaining segments and write to the output stream.
        try await concurrentlyFetchRangeGETByteStreamsAndWriteToOutputStream(
            s3: s3,
            input: input,
            // Start byte is adjusted to 2nd segment since we already did first range GET above.
            startByte: startByte + config.targetPartSizeBytes,
            endByte: endByte,
            objectSize: objectSize,
            progressTracker: progressTracker
        )

        // downloadObject call finished successfully. Return output of first range GET.
        let downloadObjectOutput = DownloadObjectOutput(getObjectOutput: firstRangeGetObjectOutput)
        onTransferComplete(
            input.transferListeners,
            input,
            downloadObjectOutput,
            SingleObjectTransferProgressSnapshot(transferredBytes: await progressTracker.transferredBytes)
        )
        return downloadObjectOutput
    }

    // Gets all segments of an S3 object starting at second subrange and writes them to the output stream.
    private func concurrentlyFetchRangeGETByteStreamsAndWriteToOutputStream(
        s3: S3Client,
        input: DownloadObjectInput,
        startByte: Int,
        endByte: Int? = nil, // Known only for "bytes=<start>-<end>".
        objectSize: Int,
        progressTracker: ObjectTransferProgressTracker
    ) async throws {
        // Must subtract 1 if there was no remainder, since we already sent
        //  a "triage" request that doubled as getting the object size.
        // E.g., say `objectSize` is 100 and part size is 10. We have 90 more bytes to fetch at this point.
        //      100 / 10 = 10. Subtract 1 to get 9, which is the remaining number of requests we need to make.
        //      Now, say object size is 103 and part size is 10. We have 93 more bytes to fetch.
        //      We need to make 10 requests to get all 93 bytes (9 x 10 byte requests, and 10th request with 3 bytes).
        //      100 / 10 = 10. So we don't subtract 1 from it if there's a remainder.
        let numRequests = (objectSize / config.targetPartSizeBytes)
        - (objectSize % config.targetPartSizeBytes == 0 ? 1 : 0)

        // Size of batch is same as the task limit per bucket.
        let batchSize = concurrentTaskLimitPerBucket
        var currentBatchStart = 0

        // Loop until all segments are retrieved and processed in batches.
        while currentBatchStart < numRequests {
            // Temporary buffer used to ensure correct ordering of data when writing to the output stream.
            var buffer = [Int: ByteStream]()

            let currentBatchEnd = min(currentBatchStart + batchSize - 1, numRequests - 1)
            try await withThrowingTaskGroup(
                // Each child task returns (request_number, stream) tuple.
                of: (Int, ByteStream).self
            ) { group in
                // Ensures taskCompleted() is called for all child tasks.
                defer {
                    Task {
                        for _ in 0..<(await taskCounter.pendingCompletionSignal) {
                            await self.taskCompleted(bucketName)
                        }
                    }
                }

                let taskCounter = DownloadTaskCounter()
                let bucketName = input.getObjectInput.bucket!

                // Add child task for each range GET in current batch.
                for numRequest in currentBatchStart...currentBatchEnd {
                    let subRangeStart = startByte + (numRequest * config.targetPartSizeBytes)
                    // End byte is inclusive, so must subtract 1 to get target amount.
                    // We don't have to worry about the case where `subRangeEnd` exceeds object size for
                    //  last segment, bc S3 automatically handles that (returns only up to available bytes).
                    var subRangeEnd = subRangeStart + config.targetPartSizeBytes - 1
                    // If it's the last request, we must use `end` if it's non-nil.
                    if let endByte, numRequest + 1 == numRequests { // + 1 bc numRequest is 0-indexed.
                        subRangeEnd = endByte
                    }
                    let rangeGetObjectInput = input.copyGetObjectInputWithPartNumberOrRange(
                        range: "bytes=\(subRangeStart)-\(subRangeEnd)"
                    )

                    group.addTask {
                        await taskCounter.incrementStart()
                        await self.waitForPermission(bucketName)
                        do {
                            try Task.checkCancellation()
                            let rangeGetObjectOutput = try await s3.getObject(input: rangeGetObjectInput)
                            // await self.taskCompleted is NOT called in this do-block (only in matching catch block).
                            // That's because connection is alive until everything is read from the body.
                            return (numRequest, rangeGetObjectOutput.body!)
                        } catch {
                            await self.taskCompleted(bucketName)
                            await taskCounter.incrementCompletion()
                            throw error
                        }
                    }
                }

                // Write results of range GETs in current batch to `input.outputStream` in order.
                var nextSegmentToProcess = currentBatchStart
                for try await (numRequest, body) in group {
                    buffer[numRequest] = body
                    while let body = buffer[nextSegmentToProcess] {
                        try await writeByteStream(
                            body,
                            to: input.outputStream,
                            input,
                            progressTracker
                        )
                        // Call taskCompleted() now that we read the entire part and connection is gonna get cleaned up.
                        await taskCompleted(bucketName)
                        await taskCounter.incrementCompletion()
                        // Discard stream after it's written to output stream.
                        buffer.removeValue(forKey: nextSegmentToProcess)
                        nextSegmentToProcess += 1
                    }
                }
            }
            // Update batch start to next batch start.
            currentBatchStart = currentBatchEnd + 1
        }
    }

    // Synchronously writes byte stream to output stream.
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

    // Parses and returns start and end values from the Range HTTP header string.
    // Supports "bytes=<start>-<end>" format and "bytes=<start>-" format.
    internal func parseBytesRange(str: String) throws -> (start: Int, end: Int?) {
        guard str.hasPrefix("bytes=") else {
            throw S3TMDownloadObjectError.invalidRangeFormat("Range must begin with \"bytes=\".")
        }

        let range = str.dropFirst(6)

        guard !range.hasPrefix("-") else {
            throw S3TMDownloadObjectError.invalidRangeFormat("Suffix range is not supported.")
        }

        let parts = range.split(separator: "-")

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
        } else { // bytes=<start>-<end>
            guard let end = Int(parts[1]) else {
                throw S3TMDownloadObjectError.invalidRangeFormat("Range end couldn't be parsed to Int!")
            }
            return (start, end)
        }
    }

    // Parses and returns the size value from the Content-Range HTTP header string.
    internal func getSizeFromContentRangeString(str: String) throws -> Int {
        let parts = str.split(separator: "/")
        guard let sizeStr = parts.last, let size = Int(sizeStr) else {
            throw S3TMDownloadObjectError.failedToDetermineObjectSize
        }
        return size
    }

    // TransferListener helper functions for `downloadObject`.

    private func onTransferInitiated(
        _ listeners: [DownloadObjectTransferListener],
        _ input: DownloadObjectInput,
        _ snapshot: SingleObjectTransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onTransferInitiated(input: input, snapshot: snapshot)
        }
    }

    private func onBytesTransferred(
        _ listeners: [DownloadObjectTransferListener],
        _ input: DownloadObjectInput,
        _ snapshot: SingleObjectTransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onBytesTransferred(input: input, snapshot: snapshot)
        }
    }

    private func onTransferComplete(
        _ listeners: [DownloadObjectTransferListener],
        _ input: DownloadObjectInput,
        _ output: DownloadObjectOutput,
        _ snapshot: SingleObjectTransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onTransferComplete(input: input, output: output, snapshot: snapshot)
        }
    }

    private func onTransferFailed(
        _ listeners: [DownloadObjectTransferListener],
        _ input: DownloadObjectInput,
        _ snapshot: SingleObjectTransferProgressSnapshot,
        _ error: Error
    ) {
        for listener in listeners {
            listener.onTransferFailed(input: input, snapshot: snapshot, error: error)
        }
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
