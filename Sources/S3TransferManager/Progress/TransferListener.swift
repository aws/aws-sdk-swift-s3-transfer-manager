//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The protocol that all concrete transfer listener types must conform to.
///
/// The transfer operations of `S3TransferManager` are "instrumented" with these transfer listener hooks.
///
/// Users can implement custom transfer listeners and provide it via the `transferListeners` property of the corresponding operation input struct.
public protocol TransferListener: Sendable {
    // UploadObject hooks.

    /// This method is invoked exactly once per transfer, right after the operation has started.
    func onUploadObjectTransferInitiated(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when some number of bytes are submitted or received. It is called at least once for a successful transfer.
    func onUploadObjectBytesTransferred(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has completed successfully. It is called exactly once for a successful transfer.
    func onUploadObjectTransferComplete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has failed. It is called exactly once for a failed transfer.
    func onUploadObjectTransferFailed(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    // DownloadObject hooks.

    /// This method is invoked exactly once per transfer, right after the operation has started.
    func onDownloadObjectTransferInitiated(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when some number of bytes are submitted or received. It is called at least once for a successful transfer.
    func onDownloadObjectBytesTransferred(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has completed successfully. It is called exactly once for a successful transfer.
    func onDownloadObjectTransferComplete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has failed. It is called exactly once for a failed transfer.
    func onDownloadObjectTransferFailed(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    // UploadDirectory hooks.

    /// This method is invoked exactly once per transfer, right after the operation has started.
    func onUploadDirectoryTransferInitiated(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has completed successfully. It is called exactly once for a successful transfer.
    func onUploadDirectoryTransferComplete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has failed. It is called exactly once for a failed transfer.
    func onUploadDirectoryTransferFailed(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    )

    // DownloadBucket hooks.

    /// This method is invoked exactly once per transfer, right after the operation has started.
    func onDownloadBucketTransferInitiated(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has completed successfully. It is called exactly once for a successful transfer.
    func onDownloadBucketTransferComplete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has failed. It is called exactly once for a failed transfer.
    func onDownloadBucketTransferFailed(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    )
}

// Default no-op implementations.
extension TransferListener {
    // UploadObject hooks.

    func onUploadObjectTransferInitiated(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {}

    func onUploadObjectBytesTransferred(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {}

    func onUploadObjectTransferComplete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {}

    func onUploadObjectTransferFailed(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {}

    // DownloadObject hooks.

    func onDownloadObjectTransferInitiated(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {}

    func onDownloadObjectBytesTransferred(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {}

    func onDownloadObjectTransferComplete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {}

    func onDownloadObjectTransferFailed(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {}

    // UploadDirectory hooks.

    func onUploadDirectoryTransferInitiated(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {}

    func onUploadDirectoryTransferComplete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {}

    func onUploadDirectoryTransferFailed(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {}

    // DownloadBucket hooks.

    func onDownloadBucketTransferInitiated(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {}

    func onDownloadBucketTransferComplete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {}

    func onDownloadBucketTransferFailed(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {}
}
