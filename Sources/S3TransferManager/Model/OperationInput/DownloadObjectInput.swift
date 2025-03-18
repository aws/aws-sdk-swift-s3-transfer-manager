//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import class Foundation.OutputStream
import struct Foundation.UUID

/// The synthetic input type for the `downloadObject` operation of `S3TransferManager`.
public struct DownloadObjectInput: TransferInput, @unchecked Sendable {
    /*
        The type is `@unchecked Sendable` because of the `outputStream: OutputStream`, which isn't thread-safe by default. However, the way `.downloadObject` is implemented makes it concurency-safe. While `.downloadObject` transfer operation _does_ concurrently get an S3 object in parts, only one thread writes to `outputStream` at any given time because writes happen with the entire batch after each batch completes their concurrent download.
     */
    /// The unique ID for the operation; can be used to log or identify a specific request.
    public let operationID: String
    /// The destination stream the downloaded object will be written to.
    public let outputStream: OutputStream
    /// The input struct for the object you want to download.
    public let getObjectInput: GetObjectInput
    /// The list of transfer listeners whose callbacks will be called by `S3TransferManager` to report on transfer status and progress.
    public let transferListeners: [TransferListener]

    /// Initializes `DownloadObjectInput` with provided parameters.
    ///
    /// - Parameters:
    ///   - outputStream: The destination of the downloaded S3 object.
    ///   - getObjectInput: An instance of the `GetObjectInput` struct.
    ///   - transferListeners: An array of `TransferListener`. The transfer status and progress of the operation will be published to each transfer listener provided here via hooks. Default value is an empty array.
    public init(
        outputStream: OutputStream,
        getObjectInput: GetObjectInput,
        transferListeners: [TransferListener] = []
    ) {
        self.operationID = UUID().uuidString
        self.outputStream = outputStream
        self.getObjectInput = getObjectInput
        self.transferListeners = transferListeners
    }

    // Internal initializer used by the `downloadBucket` operation to provide specific operation IDs for
    //  "child" requests. Allows grouping requests together by the operation IDs.
    internal init(
        operationID: String,
        outputStream: OutputStream,
        getObjectInput: GetObjectInput,
        transferListeners: [TransferListener] = []
    ) {
        self.operationID = operationID
        self.outputStream = outputStream
        self.getObjectInput = getObjectInput
        self.transferListeners = transferListeners
    }

    // MARK: - Internal helper functions for converting / transforming input(s).

    func copyGetObjectInputWithPartNumberOrRange(
        partNumber: Int? = nil,
        range: String? = nil
    ) -> GetObjectInput {
        return GetObjectInput(
            bucket: getObjectInput.bucket,
            checksumMode: getObjectInput.checksumMode,
            expectedBucketOwner: getObjectInput.expectedBucketOwner,
            ifMatch: getObjectInput.ifMatch,
            ifModifiedSince: getObjectInput.ifModifiedSince,
            ifNoneMatch: getObjectInput.ifNoneMatch,
            ifUnmodifiedSince: getObjectInput.ifUnmodifiedSince,
            key: getObjectInput.key,
            partNumber: partNumber ?? getObjectInput.partNumber,
            range: range ?? getObjectInput.range,
            requestPayer: getObjectInput.requestPayer,
            responseCacheControl: getObjectInput.responseCacheControl,
            responseContentDisposition: getObjectInput.responseContentDisposition,
            responseContentEncoding: getObjectInput.responseContentEncoding,
            responseContentLanguage: getObjectInput.responseContentLanguage,
            responseContentType: getObjectInput.responseContentType,
            responseExpires: getObjectInput.responseExpires,
            sseCustomerAlgorithm: getObjectInput.sseCustomerAlgorithm,
            sseCustomerKey: getObjectInput.sseCustomerKey,
            sseCustomerKeyMD5: getObjectInput.sseCustomerKeyMD5,
            versionId: getObjectInput.versionId
        )
    }
}
