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
    // swiftlint:disable function_body_length
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
            var payloadSize: Int = -1
            var uploadID: String = ""
            var numParts: Int = -1
            var partSize: Int = -1

            do {
                payloadSize = try await resolvePayloadSize(of: input.putObjectInput.body)
                onTransferInitiated(
                    input.transferListeners,
                    input,
                    SingleObjectTransferProgressSnapshot(transferredBytes: 0, totalBytes: payloadSize)
                )

                // If payload is below threshold, just do a single putObject.
                if payloadSize < config.multipartUploadThresholdBytes {
                    let bucketName = input.putObjectInput.bucket!
                    let putObjectOutput = try await withBucketPermission(bucketName: bucketName) {
                        try await s3.putObject(input: input.putObjectInput)
                    }

                    let uploadObjectOutput = UploadObjectOutput(putObjectOutput: putObjectOutput)
                    onBytesTransferred(
                        input.transferListeners,
                        input,
                        SingleObjectTransferProgressSnapshot(transferredBytes: payloadSize, totalBytes: payloadSize)
                    )
                    onTransferComplete(
                        input.transferListeners,
                        input,
                        uploadObjectOutput,
                        SingleObjectTransferProgressSnapshot(transferredBytes: payloadSize, totalBytes: payloadSize)
                    )
                    return uploadObjectOutput
                }

                // Otherwise, use MPU.
                (uploadID, numParts, partSize) = try await prepareMPU(
                    s3: s3,
                    payloadSize: payloadSize,
                    input: input
                )
            } catch {
                onTransferFailed(
                    input.transferListeners,
                    input,
                    SingleObjectTransferProgressSnapshot(transferredBytes: 0, totalBytes: payloadSize),
                    error
                )
                throw error
            }

            // The actor used to keep track of the number of uploaded bytes.
            let progressTracker = ObjectTransferProgressTracker()

            // Concurrently upload all the parts.
            // If an error is thrown at any point within the do-block, MPU is aborted in catch.
            do {
                let completedParts = try await uploadPartsConcurrently(
                    s3: s3,
                    input: input,
                    uploadID: uploadID,
                    numParts: numParts,
                    partSize: partSize,
                    payloadSize: payloadSize,
                    progressTracker: progressTracker
                )

                let completeMPUOutput = try await completeMPU(
                    s3: s3,
                    input: input,
                    uploadID: uploadID,
                    completedParts: completedParts,
                    payloadSize: payloadSize
                )

                let uploadObjectOutput = UploadObjectOutput(completeMultipartUploadOutput: completeMPUOutput)

                onTransferComplete(
                    input.transferListeners,
                    input,
                    uploadObjectOutput,
                    SingleObjectTransferProgressSnapshot(
                        transferredBytes: await progressTracker.transferredBytes,
                        totalBytes: payloadSize
                    )
                )
                return uploadObjectOutput
            } catch let originalError {
                onTransferFailed(
                    input.transferListeners,
                    input,
                    SingleObjectTransferProgressSnapshot(
                        transferredBytes: await progressTracker.transferredBytes,
                        totalBytes: payloadSize
                    ),
                    originalError
                )
                do {
                    try await abortMPU(
                        s3: s3,
                        input: input,
                        uploadID: uploadID,
                        originalError: originalError
                    )
                } catch let abortError {
                    throw S3TMUploadObjectError.failedToAbortMPU(
                        errorFromMPUOperation: originalError,
                        errorFromFailedAbortMPUOperation: abortError
                    )
                }
                throw originalError
            }
        }
    }
    // swiftlint:enable function_body_length

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
        s3: S3Client,
        payloadSize: Int,
        input: UploadObjectInput
    ) async throws -> (uploadID: String, numParts: Int, partSize: Int) {
        let bucketName = input.putObjectInput.bucket!

        return try await withBucketPermission(bucketName: bucketName) {
            // Determine part size. Division by 10,000 is bc MPU supports 10,000 parts maximum.
            let partSize = max(config.targetPartSizeBytes, payloadSize/10000)
            // Add 1 if there should be a last part smaller than regular part size.
            // E.g., say payloadSize is 103 and partSize is 10. Then we need 11 parts,
            //  where the 11th part is only 3 bytes long.
            let numParts = (payloadSize / partSize) + (payloadSize % partSize == 0 ? 0 : 1)
            let createMPUInput = input.getCreateMultipartUploadInput()
            let createMPUOutput = try await s3.createMultipartUpload(input: createMPUInput)

            guard let uploadID = createMPUOutput.uploadId else {
                throw S3TMUploadObjectError.failedToCreateMPU
            }
            return (uploadID, numParts, partSize)
        }
    }

    // Uploads & returns completed parts used to complete MPU.
    private func uploadPartsConcurrently(
        s3: S3Client,
        input: UploadObjectInput,
        uploadID: String,
        numParts: Int,
        partSize: Int,
        payloadSize: Int,
        progressTracker: ObjectTransferProgressTracker
    ) async throws -> [S3ClientTypes.CompletedPart] {
        var allCompletedParts: [S3ClientTypes.CompletedPart] = []
        let batchSize = concurrentTaskLimitPerBucket
        let byteStreamPartReader = ByteStreamPartReader(stream: input.putObjectInput.body!)
        let bucketName = input.putObjectInput.bucket!

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
                        return try await self.withBucketPermission(bucketName: bucketName) {
                            try Task.checkCancellation()
                            let partData = try await {
                                let partOffset = (partNumber - 1) * partSize
                                // Either take full part size or remainder (only for the last part).
                                let resolvedPartSize = min(partSize, payloadSize - partOffset)
                                return try await self.readPartData(
                                    input: input,
                                    partSize: resolvedPartSize,
                                    partOffset: partOffset,
                                    byteStreamPartReader: byteStreamPartReader
                                )
                            }()

                            let uploadPartInput = input.getUploadPartInput(
                                body: ByteStream.data(partData),
                                partNumber: partNumber,
                                uploadID: uploadID
                            )
                            let uploadPartOutput = try await s3.uploadPart(input: uploadPartInput)

                            let transferredBytes = await progressTracker.addBytes(partData.count)
                            self.onBytesTransferred(
                                input.transferListeners,
                                input,
                                SingleObjectTransferProgressSnapshot(
                                    transferredBytes: transferredBytes,
                                    totalBytes: payloadSize
                                )
                            )
                            return S3ClientTypes.CompletedPart(
                                checksumCRC32: uploadPartOutput.checksumCRC32,
                                checksumCRC32C: uploadPartOutput.checksumCRC32C,
                                checksumSHA1: uploadPartOutput.checksumSHA1,
                                checksumSHA256: uploadPartOutput.checksumSHA256,
                                eTag: uploadPartOutput.eTag,
                                partNumber: partNumber
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

        // Sort all parts by part number before returning.
        return allCompletedParts.sorted { $0.partNumber! < $1.partNumber! }
    }

    internal func readPartData(
        input: UploadObjectInput,
        partSize: Int,
        partOffset: Int,
        byteStreamPartReader: ByteStreamPartReader? = nil // Only used for stream payloads.
    ) async throws -> Data {
        var partData: Data?
        if case .data(let data) = input.putObjectInput.body {
            partData = data?[partOffset..<(partOffset + partSize)]
        } else if case .stream = input.putObjectInput.body {
            partData = try await byteStreamPartReader!.readPart(partOffset: partOffset, partSize: partSize)
        }

        guard let resolvedPartData = partData else {
            throw S3TMUploadObjectError.failedToReadPart
        }
        return resolvedPartData
    }

    private func completeMPU(
        s3: S3Client,
        input: UploadObjectInput,
        uploadID: String,
        completedParts: [S3ClientTypes.CompletedPart],
        payloadSize: Int
    ) async throws -> CompleteMultipartUploadOutput {
        let bucketName = input.putObjectInput.bucket!

        let completeMPUInput = input.getCompleteMultipartUploadInput(
            multipartUpload: S3ClientTypes.CompletedMultipartUpload(parts: completedParts),
            uploadID: uploadID,
            mpuObjectSize: payloadSize
        )

        return try await withBucketPermission(bucketName: bucketName) {
            return try await s3.completeMultipartUpload(input: completeMPUInput)
        }
    }

    private func abortMPU(
        s3: S3Client,
        input: UploadObjectInput,
        uploadID: String,
        originalError: Error
    ) async throws {
        let bucketName = input.putObjectInput.bucket!

        try await withBucketPermission(bucketName: bucketName) {
            _ = try await s3.abortMultipartUpload(input: input.getAbortMultipartUploadInput(uploadID: uploadID))
        }
    }

    // TransferListener helper functions for `uploadObject`.

    private func onTransferInitiated(
        _ listeners: [UploadObjectTransferListener],
        _ input: UploadObjectInput,
        _ snapshot: SingleObjectTransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onTransferInitiated(input: input, snapshot: snapshot)
        }
    }

    private func onBytesTransferred(
        _ listeners: [UploadObjectTransferListener],
        _ input: UploadObjectInput,
        _ snapshot: SingleObjectTransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onBytesTransferred(input: input, snapshot: snapshot)
        }
    }

    private func onTransferComplete(
        _ listeners: [UploadObjectTransferListener],
        _ input: UploadObjectInput,
        _ output: UploadObjectOutput,
        _ snapshot: SingleObjectTransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onTransferComplete(input: input, output: output, snapshot: snapshot)
        }
    }

    private func onTransferFailed(
        _ listeners: [UploadObjectTransferListener],
        _ input: UploadObjectInput,
        _ snapshot: SingleObjectTransferProgressSnapshot,
        _ error: Error
    ) {
        for listener in listeners {
            listener.onTransferFailed(input: input, snapshot: snapshot, error: error)
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
