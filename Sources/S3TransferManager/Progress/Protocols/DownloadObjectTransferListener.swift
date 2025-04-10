//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The protocol that `downloadObject` transfer listener types must conform to.
///
/// The `downloadObject` operation of `S3TransferManager` is "instrumented" with these transfer listener hooks.
///
/// Users can implement custom transfer listeners and provide it via the `transferListeners` property of the `DownloadObjectInput`.
public protocol DownloadObjectTransferListener: Sendable {
    /// This method is invoked exactly once per transfer, right after the operation has started.
    func onTransferInitiated(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when some number of bytes are submitted or received. It is called at least once for a successful transfer.
    func onBytesTransferred(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has completed successfully. It is called exactly once for a successful transfer.
    func onTransferComplete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has failed. It is called exactly once for a failed transfer.
    func onTransferFailed(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot,
        error: Error
    )
}

public extension DownloadObjectTransferListener {
    var operation: String { "DownloadObject" }
}
