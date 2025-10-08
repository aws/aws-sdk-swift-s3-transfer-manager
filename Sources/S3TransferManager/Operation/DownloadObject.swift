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
            // Deallocating buffer used by stream if stream was created with OutputStream(toBuffer:capacity:)
            //  is the responsibility of API user, as OutputStream does not expose a way to tell how it was created
            //  after the fact. So we just close the stream here.
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
        // Case 1: Config is part GET. Do a multipart GET with MPU parts.
        if config.multipartDownloadType == .part {
            return try await getObjectInParts(input, progressTracker, s3)
        } else { // Case 2: Config is range GET. Get the entire object in ranges.
            return try await getObjectInRanges(input, progressTracker, s3)
        }
    }

    private func triageGetObject(
        _ downloadObjectInput: DownloadObjectInput,
        _ getObjectInput: GetObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client
    ) async throws -> GetObjectOutput {
        let bucketName = downloadObjectInput.bucket

        let (getObjectOutput, outputData) = try await withBucketPermission(bucketName: bucketName) {
            try Task.checkCancellation()
            let getObjectOutput = try await s3.getObject(input: getObjectInput)
            // Write returned data to user-provided output stream & return.
            guard let outputData = try await getObjectOutput.body?.readData() else {
                throw S3TMDownloadObjectError.failedToReadResponseBody
            }
            return (getObjectOutput, outputData)
        }

        try await writeData(outputData, downloadObjectInput, progressTracker)
        // Remove reference to body now that it's written.
        return removeBodyFromTriageGetObjectOutput(getObjectOutput)
    }

    private func getObjectInParts(
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client
    ) async throws -> DownloadObjectOutput {
        let triageGETInput = input.deriveGetObjectInput(
            responseChecksumValidation: self.config.responseChecksumValidation,
            withPartNumber: 1
        )
        let triageGETOutput = try await triageGetObject(input, triageGETInput, progressTracker, s3)
        // Assume every part is the same size (up to last part).
        guard let partSize = triageGETOutput.contentLength else {
            throw S3TMDownloadObjectError.failedToDeterminePartSizeForPartDownload
        }
        let objectSize = try determineObjectSize(triageGETOutput)

        // Return if there's no more parts.
        guard let totalParts = triageGETOutput.partsCount, totalParts > 1 else {
            return try await publishTransferCompleteAndReturnOutput(triageGETOutput, input, progressTracker, objectSize)
        }

        // Otherwise, fetch all remaining parts and write to the output stream. Then return.
        // Use eTag value from triage response as ifMatch value in all subsequent requests for durability.
        let eTag = triageGETOutput.eTag
        try await getRemainingObjectWithPartNumbers(input, progressTracker, s3, totalParts, eTag, objectSize, partSize)
        return try await publishTransferCompleteAndReturnOutput(triageGETOutput, input, progressTracker, objectSize)
    }

    private func getRemainingObjectWithPartNumbers(
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client,
        _ totalParts: Int,
        _ eTagFromTriageGetObjectResponse: String?,
        _ objectSize: Int,
        _ partSize: Int
    ) async throws {
        let memoryConstrainedBatchSize = config.maxInMemoryBytes / partSize
        let batchSize = min(memoryConstrainedBatchSize, concurrentTaskLimitPerBucket)
        let batchMemoryUsage = batchSize * partSize

        // Process all parts in batches.
        for batchStart in stride(from: 2, to: totalParts + 1, by: batchSize) {
            let batchEnd = min(batchStart + batchSize - 1, totalParts)
            do {
                await memoryManager.waitForMemory(batchMemoryUsage)
                try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                    // Add child task for each part GET in current batch.
                    for partNumber in batchStart...batchEnd {
                        group.addTask { // Each child task returns (part_number, data) tuple.
                            return try await self.withBucketPermission(bucketName: input.bucket) {
                                try Task.checkCancellation()
                                let partGetObjectInput = input.deriveGetObjectInput(
                                    responseChecksumValidation: self.config.responseChecksumValidation,
                                    eTagFromTriageGetObjectResponse: eTagFromTriageGetObjectResponse,
                                    withPartNumber: partNumber
                                )
                                let partGetObjectOutput = try await s3.getObject(input: partGetObjectInput)
                                await progressTracker.incrementPartialDownloadCount()
                                guard let data = try await partGetObjectOutput.body?.readData() else {
                                    throw S3TMDownloadObjectError.failedToReadResponseBody
                                }
                                return (partNumber, data)
                            }
                        }
                    }

                    // Write results of part GETs in current batch to `input.outputStream` in order.
                    try await writeBatch(group, batchStart, input, progressTracker, batchMemoryUsage)
                }
            } catch {
                // This is reached in 3 scenarios:
                //  1. Download task failed before memory could be released.
                //  2. Writing data failed in writeBatch before memory could be released.
                //  3. User cancelled the root task returned by downloadObject before memory could be released.
                await memoryManager.releaseMemory(batchMemoryUsage) // Free batch memory usage.
                throw error
            }
        }

        // Check that the number of parts downloaded is as expected.
        let actualDownloadedPartsCount = await progressTracker.getPartialDownloadCount()
        // Actual number of parts downloaded by the end of this function must be totalParts - 1 because
        //  the triage getObject downloaded the first part.
        guard actualDownloadedPartsCount == totalParts - 1 else {
            throw S3TMDownloadObjectError.unexpectedNumberOfRangedGetObjectCalls(
                expected: totalParts, actual: actualDownloadedPartsCount + 1
            )
        }
    }

    private func getObjectInRanges(
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client
    ) async throws -> DownloadObjectOutput {
        // End is inclusive, so must subtract 1 to get target byte amount.
        // E.g., "bytes=0-499" returns 500 bytes.
        let triageGETInput = input.deriveGetObjectInput(
            responseChecksumValidation: self.config.responseChecksumValidation,
            withRange: "bytes=0-\(config.targetPartSizeBytes - 1)"
        )
        let triageGETOutput = try await triageGetObject(input, triageGETInput, progressTracker, s3)

        let objectSize = try determineObjectSize(triageGETOutput)

        // Return if one range GET was enough to get everything.
        if objectSize <= config.targetPartSizeBytes {
            return try await publishTransferCompleteAndReturnOutput(triageGETOutput, input, progressTracker, objectSize)
        }

        // Otherwise, fetch all remaining segments and write to the output stream.
        // Use eTag value from triage response as ifMatch value in all subsequent requests for durability.
        let eTag = triageGETOutput.eTag
        try await getRemainingObjectWithByteRanges(input, objectSize, progressTracker, s3, eTag)
        return try await publishTransferCompleteAndReturnOutput(triageGETOutput, input, progressTracker, objectSize)
    }

    private func determineObjectSize(
        _ getObjectOutput: GetObjectOutput
    ) throws -> Int {
        // Determine full object size from first output's Content-Range header.
        guard let contentRange = getObjectOutput.contentRange else {
            throw S3TMDownloadObjectError.failedToDetermineObjectSize
        }
        let parts = contentRange.split(separator: "/")
        guard let sizeStr = parts.last, let size = Int(sizeStr) else {
            throw S3TMDownloadObjectError.failedToDetermineObjectSize
        }
        return size
    }

    private func publishTransferCompleteAndReturnOutput(
        _ firstGetObjectOutput: GetObjectOutput,
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ objectSize: Int
    ) async throws -> DownloadObjectOutput {
        let downloadObjectOutput = DownloadObjectOutput(
            getObjectOutput: firstGetObjectOutput,
            objectSize: objectSize
        )
        let transferredBytes = await progressTracker.transferredBytes
        input.transferListeners.forEach { $0.onTransferComplete(
            input: input,
            output: downloadObjectOutput,
            snapshot: SingleObjectTransferProgressSnapshot(transferredBytes: transferredBytes)
        )}
        return downloadObjectOutput
    }

    private func getRemainingObjectWithByteRanges(
        _ input: DownloadObjectInput,
        _ objectSize: Int,
        _ progressTracker: ObjectTransferProgressTracker,
        _ s3: S3Client,
        _ eTagFromTriageGetObjectResponse: String?
    ) async throws {
        /*
            Must subtract 1 if there was no remainder, since we already sent a "triage" request that doubled as getting the object size. E.g., say `objectSize` is 100 and part size is 10. We have 90 more bytes to fetch at this point. 100 / 10 = 10. Subtract 1 to get 9, which is the remaining number of requests we need to make. Now, say object size is 103 and part size is 10. We have 93 more bytes to fetch. We need to make 10 requests to get all 93 bytes (9 x 10 byte requests, and 10th request with 3 bytes). 100 / 10 = 10. So we don't subtract 1 from it if there's a remainder.
         */
        let numberOfRequests = (objectSize / config.targetPartSizeBytes)
        - (objectSize % config.targetPartSizeBytes == 0 ? 1 : 0)

        let memoryConstrainedBatchSize = config.maxInMemoryBytes / config.targetPartSizeBytes
        let batchSize = min(memoryConstrainedBatchSize, concurrentTaskLimitPerBucket)
        let batchMemoryUsage = batchSize * config.targetPartSizeBytes

        for batchStart in stride(from: 0, to: numberOfRequests, by: batchSize) {
            let batchEnd = min(batchStart + batchSize - 1, numberOfRequests - 1)

            do {
                await memoryManager.waitForMemory(batchMemoryUsage)
                try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                    // Add child task for each range GET in current batch.
                    for requestNum in batchStart...batchEnd {
                        let rangeGetObjectInput = constructRangetGetObjectInput(
                            input, requestNum, objectSize, eTagFromTriageGetObjectResponse
                        )
                        group.addTask { // Each child task returns (request_number, data) tuple.
                            return try await self.withBucketPermission(bucketName: input.bucket) {
                                try Task.checkCancellation()
                                let rangeGetObjectOutput = try await s3.getObject(input: rangeGetObjectInput)
                                await progressTracker.incrementPartialDownloadCount()
                                guard let data = try await rangeGetObjectOutput.body?.readData() else {
                                    throw S3TMDownloadObjectError.failedToReadResponseBody
                                }
                                return (requestNum, data)
                            }
                        }
                    }

                    // Write results of range GETs in current batch to `input.outputStream` in order.
                    try await writeBatch(group, batchStart, input, progressTracker, batchMemoryUsage)
                }
            } catch {
                // This is reached in 3 scenarios:
                //  1. Download task failed before memory could be released.
                //  2. Writing data failed in writeBatch before memory could be released.
                //  3. User cancelled the root task returned by downloadObject before memory could be released.
                await memoryManager.releaseMemory(batchMemoryUsage) // Free batch memory usage.
                throw error
            }
        }

        // Check that the number of range requests made is as expected.
        let actualRequestCount = await progressTracker.getPartialDownloadCount()
        guard actualRequestCount == numberOfRequests else {
            throw S3TMDownloadObjectError.unexpectedNumberOfRangedGetObjectCalls(
                expected: numberOfRequests, actual: actualRequestCount
            )
        }
    }

    private func constructRangetGetObjectInput(
        _ input: DownloadObjectInput,
        _ requestNum: Int,
        _ objectSize: Int,
        _ eTagFromTriageGetObjectResponse: String?
    ) -> GetObjectInput {
        // Subrange start is always offset by +1 due to triage getObject request.
        let subRangeStart = (requestNum + 1) * config.targetPartSizeBytes
        // End byte is inclusive, so must subtract 1 to get target byte amount.
        let subRangeEnd = min(subRangeStart + config.targetPartSizeBytes - 1, objectSize - 1)
        return input.deriveGetObjectInput(
            responseChecksumValidation: self.config.responseChecksumValidation,
            eTagFromTriageGetObjectResponse: eTagFromTriageGetObjectResponse,
            withRange: "bytes=\(subRangeStart)-\(subRangeEnd)"
        )
    }

    private func writeBatch(
        _ group: ThrowingTaskGroup<(Int, Data), any Error>,
        _ batchStart: Int,
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker,
        _ batchMemoryUsage: Int
    ) async throws {
        // Temporary buffer used to ensure correct ordering of data when writing to the output stream.
        var buffer = [Int: Data]()

        var nextDataToProcess = batchStart
        for try await (index, data) in group {
            buffer[index] = data
            while let nextData = buffer[nextDataToProcess] {
                try await writeData(nextData, input, progressTracker)
                // Discard data after it's written to the output stream.
                buffer.removeValue(forKey: nextDataToProcess)
                nextDataToProcess += 1
            }
        }
        // Now that all data in batch is written, release batch memory usage.
        await memoryManager.releaseMemory(batchMemoryUsage)
    }

    internal func writeData(
        _ data: Data,
        _ input: DownloadObjectInput,
        _ progressTracker: ObjectTransferProgressTracker
    ) async throws {
        if input.outputStream.streamStatus == .notOpen { input.outputStream.open() }
        // Write to output stream with retry logic for transient failures.
        var bytesWritten = 0
        var remainingData = data

        while !remainingData.isEmpty {
            let written = remainingData.withUnsafeBytes { bufferPointer -> Int in
                guard let baseAddress = bufferPointer.baseAddress else { return -1 }
                return input.outputStream.write(
                    baseAddress.assumingMemoryBound(to: UInt8.self),
                    maxLength: bufferPointer.count
                )
            }

            if written < 0 {
                if input.outputStream.streamError != nil {
                    throw S3TMDownloadObjectError.failedToWriteToOutputStream
                }
                // Jittered backoff to avoid retry storms
                let jitter = UInt64.random(in: 1_000_000...10_000_000) // 1-10ms
                try await Task.sleep(nanoseconds: jitter)
                continue
            }

            if written == 0 {
                throw S3TMDownloadObjectError.failedToWriteToOutputStream
            }

            bytesWritten += written
            remainingData = remainingData.dropFirst(written)
        }

        let transferredBytes = await progressTracker.addBytes(bytesWritten)
        input.transferListeners.forEach { $0.onBytesTransferred(
            input: input,
            snapshot: SingleObjectTransferProgressSnapshot(transferredBytes: transferredBytes)
        )}
    }

    private func removeBodyFromTriageGetObjectOutput(
        _ triageGetObjectOutput: GetObjectOutput
    ) -> GetObjectOutput {
        return GetObjectOutput(
            acceptRanges: triageGetObjectOutput.acceptRanges,
            body: nil,
            bucketKeyEnabled: triageGetObjectOutput.bucketKeyEnabled,
            cacheControl: triageGetObjectOutput.cacheControl,
            checksumCRC32: triageGetObjectOutput.checksumCRC32,
            checksumCRC32C: triageGetObjectOutput.checksumCRC32C,
            checksumCRC64NVME: triageGetObjectOutput.checksumCRC64NVME,
            checksumSHA1: triageGetObjectOutput.checksumSHA1,
            checksumSHA256: triageGetObjectOutput.checksumSHA256,
            checksumType: triageGetObjectOutput.checksumType,
            contentDisposition: triageGetObjectOutput.contentDisposition,
            contentEncoding: triageGetObjectOutput.contentEncoding,
            contentLanguage: triageGetObjectOutput.contentLanguage,
            contentLength: triageGetObjectOutput.contentLength,
            contentRange: triageGetObjectOutput.contentRange,
            contentType: triageGetObjectOutput.contentType,
            deleteMarker: triageGetObjectOutput.deleteMarker,
            eTag: triageGetObjectOutput.eTag,
            expiration: triageGetObjectOutput.expiration,
            expires: triageGetObjectOutput.expires,
            lastModified: triageGetObjectOutput.lastModified,
            metadata: triageGetObjectOutput.metadata,
            missingMeta: triageGetObjectOutput.missingMeta,
            objectLockLegalHoldStatus: triageGetObjectOutput.objectLockLegalHoldStatus,
            objectLockMode: triageGetObjectOutput.objectLockMode,
            objectLockRetainUntilDate: triageGetObjectOutput.objectLockRetainUntilDate,
            partsCount: triageGetObjectOutput.partsCount,
            replicationStatus: triageGetObjectOutput.replicationStatus,
            requestCharged: triageGetObjectOutput.requestCharged,
            restore: triageGetObjectOutput.restore,
            serverSideEncryption: triageGetObjectOutput.serverSideEncryption,
            sseCustomerAlgorithm: triageGetObjectOutput.sseCustomerAlgorithm,
            sseCustomerKeyMD5: triageGetObjectOutput.sseCustomerKeyMD5,
            ssekmsKeyId: triageGetObjectOutput.ssekmsKeyId,
            storageClass: triageGetObjectOutput.storageClass,
            tagCount: triageGetObjectOutput.tagCount,
            versionId: triageGetObjectOutput.versionId,
            websiteRedirectLocation: triageGetObjectOutput.websiteRedirectLocation
        )
    }
}

/// A non-exhaustive list of errors that can be thrown by the `downloadObject` operation of `S3TransferManager`.
public enum S3TMDownloadObjectError: Error {
    case failedToReadResponseBody
    case failedToDetermineObjectSize
    case invalidDownloadConfiguration
    case failedToWriteToOutputStream
    case invalidRangeFormat(String)
    case unexpectedNumberOfRangedGetObjectCalls(expected: Int, actual: Int)
    case unexpectedNumberOfPartNumberGetObjectCalls(expected: Int, actual: Int)
    case failedToDeterminePartSizeForPartDownload
}
