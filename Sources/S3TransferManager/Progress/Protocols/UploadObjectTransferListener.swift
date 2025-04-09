//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The protocol that `uploadObject` transfer listener types must conform to.
///
/// The `uploadObject` operation of `S3TransferManager` is "instrumented" with these transfer listener hooks.
///
/// Users can implement custom transfer listeners and provide it via the `transferListeners` property of the `UploadObjectInput`.
public protocol UploadObjectTransferListener: Sendable {
    /// This method is invoked exactly once per transfer, right after the operation has started.
    func onTransferInitiated(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when some number of bytes are submitted or received. It is called at least once for a successful transfer.
    func onBytesTransferred(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has completed successfully. It is called exactly once for a successful transfer.
    func onTransferComplete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    )

    /// This method is invoked when the transfer has failed. It is called exactly once for a failed transfer.
    func onTransferFailed(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot,
        error: Error
    )
}

public extension UploadObjectTransferListener {
    var operation: String { "UploadObject" }
}
