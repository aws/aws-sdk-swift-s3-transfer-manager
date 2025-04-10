//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import struct Foundation.URL
import struct Foundation.UUID

/// The synthetic input type for the `downloadBucket` operation of `S3TransferManager`.
public struct DownloadBucketInput: Sendable, Identifiable {
    /// The unique ID for the operation; can be used to log or identify a specific request.
    public let id: String = UUID().uuidString
    /// The source S3 bucket.
    public let bucket: String
    /// The destination directory URL.
    public let destination: URL
    /// The common prefix of S3 objects you want to download.
    public let s3Prefix: String?
    /// The delimiter used by S3 objects you want to download.
    public let s3Delimiter: String
    /// The closure used to skip downloading S3 objects that meet the filter criteria. The returned boolean determined whether the object gets downloaded or not (i.e., `true` to downoad, `false` to filter out).
    public let filter: @Sendable (S3ClientTypes.Object) -> Bool
    /// The closure that allows customizing each individual `GetObjectInput` used behind the scenes for each `downloadObject` transfer operation.
    public let getObjectRequestCallback: @Sendable (GetObjectInput) -> GetObjectInput
    /// The closure that handles each `downloadObject` transfer failure.
    public let failurePolicy: FailurePolicy<DownloadBucketInput>
    /// The list of transfer listeners whose callbacks will be called by `S3TransferManager` to report on directory transfer status and progress.
    public let directoryTransferListeners: [DownloadBucketTransferListener]
    /// The transfer listener factory closure called by `S3TransferManager` to create listeners for individual object transfer. Use to track download status and progress of individual objects in the bucket.
    public let objectTransferListenerFactory: @Sendable (GetObjectInput) async -> [DownloadObjectTransferListener]

    /// Initializes `DownloadBucketInput` with provided parameters.
    ///
    /// - Parameters:
    ///   - bucket: The name of the S3 bucket to download.
    ///   - destination: The URL for the local directory to download the S3 bucket to.
    ///   - s3Prefix: If non-nil, only the S3 objects that have this prefix will be downloaded. All downloaded files will be saved to the `destination` with this prefix removed from the file names. E.g., if `destination` is `"/dir1/dir2/"` and `s3Prefix` is `"dir3/dir4"`, and object key is `"dir3/dir4/dir5/file.txt"`, the object will be saved to `"/dir1/dir2/dir5/file.txt"`, which is destination + (object key - prefix). Default value is `nil`, meaning every object in the bucket will be downloaded.
    ///   - s3Delimiter: Specifies what delimiter is used by the S3 objects you want to download. Objects will be saved to the file location resolved by replacing the specified `s3Delimiter` with system default path separator `"/"`. E.g., if `destination` is `"/dir1"`, `s3Delimiter` is `"-"`, and the key of the S3 object being downloaded is `"dir2-dir3-dir4-file.txt"`, the object will be saved to `"/dir1/dir2/dir3/dir4/file.txt"`.  Default value is `"/"`, which is the system default path separator for all Apple platforms and Linux distros.
    ///   - filter: A closure that allows skipping unwanted S3 objects. Skipped objects do not get downloaded. Default behavior is a closure that just returns `true`, which filters nothing.
    ///   - getObjectRequestCallback: A closure that allows customizing the individual `GetObjectInput` passed to each part or range `getObject` calls used behind the scenes. Default behavior is a no-op closure that returns provided `GetObjectInput` without modification.
    ///   - failurePolicy: A closure that handles `downloadObject` operation failures. Default behavior is `CannedFailurePolicy.rethrowExceptionToTerminateRequest()`, which simply bubbles up the error to the caller and terminates the entire `downloadBucket` operation.
    ///   - directoryTransferListeners: An array of `DownloadBucketTransferListener`. The transfer status and progress of the directory transfer operation will be published to each transfer listener provided here. Default value is an empty array.
    ///   - objectTransferListenerFactory: A closure that creates and returns an array of `DownloadObjectTransferListener` instances for each indiviual object transfer. The transfer status and progress of each individual object transfer operation will be published to the listeners created here. Default is a closure that returns an empty array.
    public init(
        bucket: String,
        destination: URL,
        s3Prefix: String? = nil,
        s3Delimiter: String = "/",
        filter: @Sendable @escaping (S3ClientTypes.Object) -> Bool = { _ in return true },
        getObjectRequestCallback: @Sendable @escaping (GetObjectInput) -> GetObjectInput = { input in
            return input
        },
        failurePolicy: @escaping FailurePolicy<DownloadBucketInput> = CannedFailurePolicy
            .rethrowExceptionToTerminateRequest(),
        directoryTransferListeners: [DownloadBucketTransferListener] = [],
        objectTransferListenerFactory: @Sendable @escaping (
            GetObjectInput
        ) async -> [DownloadObjectTransferListener] = { _ in [] }
    ) {
        self.bucket = bucket
        self.destination = destination
        self.s3Prefix = s3Prefix
        self.s3Delimiter = s3Delimiter
        self.filter = filter
        self.getObjectRequestCallback = getObjectRequestCallback
        self.failurePolicy = failurePolicy
        self.directoryTransferListeners = directoryTransferListeners
        self.objectTransferListenerFactory = objectTransferListenerFactory
    }
}
