//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import struct Foundation.URL
import struct Foundation.UUID

/// The synthetic input type for the `uploadDirectory` operation of `S3TransferManager`.
public struct UploadDirectoryInput {
    /// The unique ID for the operation; can be used to log or identify a specific request.
    public let operationID: String = UUID().uuidString
    /// The destination S3 bucket.
    public let bucket: String
    /// The source directory URL.
    public let source: URL
    /// The flag for whether to follow symlinks or not during upload.
    public let followSymbolicLinks: Bool
    /// The flag for whether to recurse into nested directories or not during upload.
    public let recursive: Bool
    /// The common prefix that gets prepended to object keys of all uploaded S3 objects.
    public let s3Prefix: String?
    /// The delimiter that replaces the default path separator `"/"` in object keys of all uploaded S3 objects.
    public let s3Delimiter: String
    /// The closure that allows customizing each individual `PutObjectinput` used behind the scenes for each `uploadObject` transfer operation.
    public let putObjectRequestCallback: @Sendable (PutObjectInput) -> PutObjectInput
    /// The closure that handles each `uploadObject` transfer failure.
    public let failurePolicy: FailurePolicy<UploadDirectoryInput>
    /// The list of transfer listeners whose callbacks will be called by `S3TransferManager` to report on transfer status and progress.
    public let transferListeners: [UploadDirectoryTransferListener]
    /// The list of transfer listeners whose callbacks will be called by `S3TransferManager` to report on transfer status and progress.
    public let objectTransferListeners: [UploadObjectTransferListener]

    /// Initializes `UploadDirectoryInput` with provided parameters.
    ///
    /// - Parameters:
    ///   - bucket: The name of the S3 bucket to upload the local directory to.
    ///   - source: The URL for the local directory to upload.
    ///   - followSymbolicLinks: The flag for whether to follow symlinks or not. Default value is `false`.
    ///   - recursive: The flag for whether to recursively upload `source` including contents of all subdirectories. Default value is `false`.
    ///   - s3Prefix: The S3 key prefix prepended to object keys during uploads. E.g., if this value is set to `"pre-"`, `source` is set to `/dir1`, and the file being uploaded is `/dir1/dir2/file.txt`, then the uploaded S3 object would have the key `pre-dir2/file.txt`. Default value is `nil`.
    ///   - s3Delimiter: The path separator to use in the object key. E.g., if `source` is `/dir1`, `s3Delimiter` is `"-"`, and the file being uploaded is `/dir1/dir2/dir3/dir4/file.txt`, then the uploaded S3 object will have the key `dir2-dir3-dir4-file.txt`. Default value is `"/"`, which is the system default path separator for all Apple platforms and Linux distros.
    ///   - putObjectRequestCallback: A closure that allows customizing the individual `PutObjectInput` passed to each part `putObject` calls used behind the scenes. Default behavior is a no-op closure that returns provided `PutObjectInput` without modification.
    ///   - failurePolicy: A closure that handles `uploadObject` operation failures. Default behavior is `CannedFailurePolicy.rethrowExceptionToTerminateRequest`, which simply bubbles up the error to the caller and terminates the entire `uploadDirectory` operation.
    ///   - transferListeners: An array of `TransferListener`. The transfer status and progress of the operation will be published to each transfer listener provided here via hooks. Default value is an empty array.
    public init(
        bucket: String,
        source: URL,
        followSymbolicLinks: Bool = false,
        recursive: Bool = false,
        s3Prefix: String? = nil,
        s3Delimiter: String = "/",
        putObjectRequestCallback: @Sendable @escaping (PutObjectInput) -> PutObjectInput = { input in
            return input
        },
        failurePolicy: @escaping FailurePolicy<UploadDirectoryInput> = CannedFailurePolicy.rethrowExceptionToTerminateRequest(),
        transferListeners: [UploadDirectoryTransferListener] = [],
        objectTransferListeners: [UploadObjectTransferListener] = []
    ) throws {
        self.bucket = bucket
        self.source = source
        self.followSymbolicLinks = followSymbolicLinks
        self.recursive = recursive
        self.s3Prefix = s3Prefix
        self.s3Delimiter = s3Delimiter
        self.putObjectRequestCallback = putObjectRequestCallback
        self.failurePolicy = failurePolicy
        self.transferListeners = transferListeners
        self.objectTransferListeners = objectTransferListeners
        try validateSourceURL(source)
    }

    private func validateSourceURL(_ source: URL) throws {
        let urlProperties = try source.resourceValues(forKeys: [.isDirectoryKey])
        guard urlProperties.isDirectory ?? false else {
            throw S3TMUploadDirectoryError.InvalidSourceURL(
                "Invalid source: provided source URL is not a directory URL."
            )
        }
    }
}
