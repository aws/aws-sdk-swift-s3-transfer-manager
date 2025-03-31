//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The protocol that `downloadBucket` transfer listener types must conform to.
///
/// The `downloadBucket` operation of `S3TransferManager` is "instrumented" with these transfer listener hooks.
///
/// Users can implement custom transfer listeners and provide it via the `transferListeners` property of the `DownloadBucketInput`.
public protocol DownloadBucketTransferListener: Sendable {
    /// This method is invoked exactly once per transfer, right after the operation has started.
    func onTransferInitiated(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has completed successfully. It is called exactly once for a successful transfer.
    func onTransferComplete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has failed. It is called exactly once for a failed transfer.
    func onTransferFailed(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    )
}

public extension DownloadBucketTransferListener {
    var operation: String { "DownloadBucket" }
}
