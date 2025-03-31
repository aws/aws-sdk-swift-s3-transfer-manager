//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The protocol that `uploadDirectory` transfer listener types must conform to.
///
/// The `uploadDirectory` operation of `S3TransferManager` is "instrumented" with these transfer listener hooks.
///
/// Users can implement custom transfer listeners and provide it via the `transferListeners` property of the `UploadDirectoryInput`.
public protocol UploadDirectoryTransferListener: Sendable {
    /// This method is invoked exactly once per transfer, right after the operation has started.
    func onTransferInitiated(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has completed successfully. It is called exactly once for a successful transfer.
    func onTransferComplete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has failed. It is called exactly once for a failed transfer.
    func onTransferFailed(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    )
}

public extension UploadDirectoryTransferListener {
    var operation: String { "UploadDirectory" }
}
