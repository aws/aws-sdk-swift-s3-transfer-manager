//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import enum Smithy.ByteStream
import struct Foundation.Data

public extension S3TransferManager {
    /// Uploads a single object to an S3 bucket.
    ///
    /// Returns a `Task` immediately after function call; upload is handled in the background using asynchronous child tasks.
    /// If the `Task` returned by the function gets cancelled, all child tasks also get cancelled automatically and any in-progress multipart upload (MPU) gets aborted.
    ///
    /// - Parameters:
    ///   - input: An instance of `UploadObjectInput`, the synthetic input type specific to this operation of `S3TransferManager`.
    /// - Returns: An asynchronous `Task<UploadObjectOutput, Error>` that can be optionally waited on or cancelled as needed.
    ///
    /// This operation does not support uploading a stream payload of unknown length.
    func uploadObject(input: UploadObjectInput) throws -> Task<UploadObjectOutput, Error> {
        return Task {
            let s3 = config.s3Client
            var uploadID: String = ""
            var payloadSize = -1, numParts = -1, partSize = -1

            do {
                payloadSize = try await resolvePayloadSize(of: input.body)
                let snapshot = SingleObjectTransferProgressSnapshot(transferredBytes: 0, totalBytes: payloadSize)
                input.transferListeners.forEach { $0.onTransferInitiated(input: input, snapshot: snapshot) }

                if payloadSize < config.multipartUploadThresholdBytes {
                    return try await singlePutObject(input: input, payloadSize: payloadSize, s3: s3)
                }

                (uploadID, numParts, partSize) = try await prepareMPU(input: input, payloadSize: payloadSize, s3: s3)
            } catch {
                let snapshot = SingleObjectTransferProgressSnapshot(transferredBytes: 0, totalBytes: payloadSize)
                input.transferListeners.forEach { $0.onTransferFailed(input: input, snapshot: snapshot, error: error) }
                throw error
            }

            // Concurrently upload all the parts.
            let progressTracker = ObjectTransferProgressTracker()
            do {
                return try await mpu(
                    input: input,
                    numParts: numParts,
                    partSize: partSize,
                    payloadSize: payloadSize,
                    progressTracker: progressTracker,
                    s3: s3,
                    uploadID: uploadID
                )
            } catch let originalError {
                try await handleMPUError(
                    input: input,
                    originalError: originalError,
                    payloadSize: payloadSize,
                    progressTracker: progressTracker,
                    s3: s3,
                    uploadID: uploadID
                )
                throw originalError
            }
        }
    }

    private func singlePutObject(
        input: UploadObjectInput,
        payloadSize: Int,
        s3: S3Client
    ) async throws -> UploadObjectOutput {
        let putObjectOutput = try await withBucketPermission(bucketName: input.bucket) {
            try await s3.putObject(input: input.derivePutObjectInput())
        }

        let uploadObjectOutput = UploadObjectOutput(putObjectOutput: putObjectOutput)
        let snapshot = SingleObjectTransferProgressSnapshot(
            transferredBytes: payloadSize,
            totalBytes: payloadSize
        )
        input.transferListeners.forEach { $0.onBytesTransferred(
            input: input,
            snapshot: snapshot
        )}
        input.transferListeners.forEach { $0.onTransferComplete(
            input: input,
            output: uploadObjectOutput,
            snapshot: snapshot
        )}
        return uploadObjectOutput
    }

    private func mpu(
        input: UploadObjectInput,
        numParts: Int,
        partSize: Int,
        payloadSize: Int,
        progressTracker: ObjectTransferProgressTracker,
        s3: S3Client,
        uploadID: String
    ) async throws -> UploadObjectOutput {
        let completedParts = try await uploadPartsConcurrently(
            input: input,
            numParts: numParts,
            partSize: partSize,
            payloadSize: payloadSize,
            progressTracker: progressTracker,
            s3: s3,
            uploadID: uploadID
        )
        let completeMPUOutput = try await completeMPU(completedParts, input, payloadSize, s3, uploadID)
        let uploadObjectOutput = UploadObjectOutput(completeMultipartUploadOutput: completeMPUOutput)
        let snapshot = SingleObjectTransferProgressSnapshot(
            transferredBytes: await progressTracker.transferredBytes,
            totalBytes: payloadSize
        )
        input.transferListeners.forEach {
            $0.onTransferComplete(input: input, output: uploadObjectOutput, snapshot: snapshot)
        }
        return uploadObjectOutput
    }

    private func handleMPUError(
        input: UploadObjectInput,
        originalError: Error,
        payloadSize: Int,
        progressTracker: ObjectTransferProgressTracker,
        s3: S3Client,
        uploadID: String
    ) async throws {
        let snapshot = SingleObjectTransferProgressSnapshot(
            transferredBytes: await progressTracker.transferredBytes,
            totalBytes: payloadSize
        )
        input.transferListeners.forEach { $0.onTransferFailed(input: input, snapshot: snapshot, error: originalError) }
        do {
            try await withBucketPermission(bucketName: input.bucket) {
                _ = try await s3.abortMultipartUpload(input: input.deriveAbortMultipartUploadInput(uploadID: uploadID))
            }
        } catch let abortError {
            throw S3TMUploadObjectError.failedToAbortMPU(
                errorFromMPUOperation: originalError,
                errorFromFailedAbortMPUOperation: abortError
            )
        }
    }

    internal func resolvePayloadSize(of body: ByteStream?) async throws -> Int {
        switch body {
        case .data(let data):
            return data?.count ?? 0
        case .stream(let stream):
            if let length = stream.length {
                return length
            } else {
                throw S3TMUploadObjectError.streamPayloadOfUnknownLength
            }
        default:
            return 0
        }
    }

    private func prepareMPU(
        input: UploadObjectInput,
        payloadSize: Int,
        s3: S3Client
    ) async throws -> (uploadID: String, numParts: Int, partSize: Int) {
        return try await withBucketPermission(bucketName: input.bucket) {
            // Determine part size. Division by 10,000 is bc MPU supports 10,000 parts maximum.
            let partSize = max(config.targetPartSizeBytes, payloadSize/10000)
            // Add 1 if there should be a last part smaller than regular part size.
            // E.g., say payloadSize is 103 and partSize is 10. Then we need 11 parts,
            //  where the 11th part is only 3 bytes long.
            let numParts = (payloadSize / partSize) + (payloadSize % partSize == 0 ? 0 : 1)
            let createMPUInput = input.deriveCreateMultipartUploadInput()
            let createMPUOutput = try await s3.createMultipartUpload(input: createMPUInput)

            guard let uploadID = createMPUOutput.uploadId else {
                throw S3TMUploadObjectError.failedToCreateMPU
            }
            return (uploadID, numParts, partSize)
        }
    }

    // Uploads & returns completed parts used to complete MPU.
    private func uploadPartsConcurrently(
        input: UploadObjectInput,
        numParts: Int,
        partSize: Int,
        payloadSize: Int,
        progressTracker: ObjectTransferProgressTracker,
        s3: S3Client,
        uploadID: String
    ) async throws -> [S3ClientTypes.CompletedPart] {
        var allCompletedParts: [S3ClientTypes.CompletedPart] = []
        let batchSize = concurrentTaskLimitPerBucket
        let byteStreamPartReader = ByteStreamPartReader(stream: input.body)

        // Process parts in batches.
        // Loop to numParts + 1; handles edgecase when last part is start to a new batch.
        for batchStart in stride(from: 1, to: numParts + 1, by: batchSize) {
            let batchEnd = min(batchStart + batchSize - 1, numParts)

            // Process each batch with its own TaskGroup.
            let batchCompletedParts = try await withThrowingTaskGroup(
                // Child task returns a completed part that contains S3's checksum & part number.
                of: S3ClientTypes.CompletedPart.self,
                // Task group returns completed parts in the batch.
                returning: [S3ClientTypes.CompletedPart].self
            ) { group in
                for partNumber in batchStart...batchEnd {
                    try Task.checkCancellation()
                    group.addTask {
                        return try await self.withBucketPermission(bucketName: input.bucket) {
                            return try await self.uploadPart(
                                byteStreamPartReader: byteStreamPartReader,
                                input: input,
                                partNumber: partNumber,
                                partSize: partSize,
                                payloadSize: payloadSize,
                                progressTracker: progressTracker,
                                s3: s3,
                                uploadID: uploadID
                            )
                        }
                    }
                }
                // Collect the results from this batch.
                var batchResults: [S3ClientTypes.CompletedPart] = []
                for try await part in group {
                    batchResults.append(part)
                }
                return batchResults
            }
            // Add this batch's results to our overall collection.
            allCompletedParts.append(contentsOf: batchCompletedParts)
        }
        // Durability validation for number of uploaded parts.
        guard allCompletedParts.count == numParts else {
            throw S3TMUploadObjectError.incorrectNumberOfUploadedParts(
                message: "Expected \(numParts) uploaded parts but uploaded "
                + "\(allCompletedParts.count) parts instead."
            )
        }
        // Sort all parts by part number before returning.
        return allCompletedParts.sorted { $0.partNumber! < $1.partNumber! }
    }

    private func uploadPart(
        byteStreamPartReader: ByteStreamPartReader,
        input: UploadObjectInput,
        partNumber: Int,
        partSize: Int,
        payloadSize: Int,
        progressTracker: ObjectTransferProgressTracker,
        s3: S3Client,
        uploadID: String
    ) async throws -> S3ClientTypes.CompletedPart {
        try Task.checkCancellation()
        let partData = try await {
            let partOffset = (partNumber - 1) * partSize
            // Either take full part size or remainder (only for the last part).
            let resolvedPartSize = min(partSize, payloadSize - partOffset)
            let partData = try await self.readPartData(
                input: input,
                partSize: resolvedPartSize,
                partOffset: partOffset,
                byteStreamPartReader: byteStreamPartReader
            )
            guard partData.count == resolvedPartSize else {
                throw S3TMUploadObjectError.incorrectSizePartRead(expected: resolvedPartSize, actual: partData.count)
            }
            return partData
        }()

        let uploadPartInput = input.deriveUploadPartInput(
            body: ByteStream.data(partData),
            partNumber: partNumber,
            uploadID: uploadID
        )
        let uploadPartOutput = try await s3.uploadPart(input: uploadPartInput)

        let snapshot = SingleObjectTransferProgressSnapshot(
            transferredBytes: await progressTracker.addBytes(partData.count),
            totalBytes: payloadSize
        )
        input.transferListeners.forEach { $0.onBytesTransferred(
            input: input,
            snapshot: snapshot
        )}
        return S3ClientTypes.CompletedPart(
            checksumCRC32: uploadPartOutput.checksumCRC32,
            checksumCRC32C: uploadPartOutput.checksumCRC32C,
            checksumSHA1: uploadPartOutput.checksumSHA1,
            checksumSHA256: uploadPartOutput.checksumSHA256,
            eTag: uploadPartOutput.eTag,
            partNumber: partNumber
        )
    }

    internal func readPartData(
        input: UploadObjectInput,
        partSize: Int,
        partOffset: Int,
        byteStreamPartReader: ByteStreamPartReader? = nil // Only used for stream payloads.
    ) async throws -> Data {
        var partData: Data?
        if case .data(let data) = input.body {
            partData = data?[partOffset..<(partOffset + partSize)]
        } else if case .stream = input.body {
            partData = try await byteStreamPartReader!.readPart(partOffset: partOffset, partSize: partSize)
        }
        guard let resolvedPartData = partData else {
            throw S3TMUploadObjectError.failedToReadPart
        }
        return resolvedPartData
    }

    private func completeMPU(
        _ completedParts: [S3ClientTypes.CompletedPart],
        _ input: UploadObjectInput,
        _ payloadSize: Int,
        _ s3: S3Client,
        _ uploadID: String
    ) async throws -> CompleteMultipartUploadOutput {
        let completeMPUInput = input.deriveCompleteMultipartUploadInput(
            multipartUpload: S3ClientTypes.CompletedMultipartUpload(parts: completedParts),
            uploadID: uploadID,
            mpuObjectSize: payloadSize
        )
        return try await withBucketPermission(bucketName: input.bucket) {
            return try await s3.completeMultipartUpload(input: completeMPUInput)
        }
    }
}

/// A non-exhaustive list of errors that can be thrown by the `uploadObject` operation of `S3TransferManager`.
public enum S3TMUploadObjectError: Error {
    case streamPayloadOfUnknownLength
    case failedToCreateMPU
    case failedToReadPart
    case failedToAbortMPU(errorFromMPUOperation: Error, errorFromFailedAbortMPUOperation: Error)
    case unseekableStreamPayload
    case incorrectNumberOfUploadedParts(message: String)
    case incorrectSizePartRead(expected: Int, actual: Int)
}

// An actor used to read a ByteStream in parts while ensuring concurrency-safety.
internal actor ByteStreamPartReader {
    private let stream: ByteStream

    init(stream: ByteStream) {
        self.stream = stream
    }

    func readPart(partOffset: Int, partSize: Int) throws -> Data {
        if case .stream(let stream) = stream, stream.isSeekable {
            try stream.seek(toOffset: partOffset)
            return try stream.read(upToCount: partSize)!
        } else {
            throw S3TMUploadObjectError.unseekableStreamPayload
        }
    }
}
