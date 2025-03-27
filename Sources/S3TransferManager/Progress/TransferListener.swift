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
public protocol UploadObjectTransferListener: Sendable {
    // UploadObject hooks.

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
        snapshot: SingleObjectTransferProgressSnapshot
    )
}

public extension UploadObjectTransferListener {
    static var logger: UploadObjectTransferListener {
        UploadObjectLoggingTransferListener()
    }

    static var asyncStreaming: UploadObjectTransferListener {
        UploadObjectStreamingTransferListener()
    }

    var operation: String { "UploadObject" }
}

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
        snapshot: SingleObjectTransferProgressSnapshot
    )
}

public extension DownloadObjectTransferListener {

    static var logger: DownloadObjectTransferListener {
        DownloadObjectLoggingTransferListener()
    }

    static var asyncStreaming: DownloadObjectTransferListener {
        DownloadObjectStreamingTransferListener()
    }

    var operation: String { "DownloadObject" }
}

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

    static var logger: UploadDirectoryTransferListener {
        UploadDirectoryLoggingTransferListener()
    }

    static var asyncStreaming: UploadDirectoryTransferListener {
        UploadDirectoryStreamingTransferListener()
    }

    var operation: String { "UploadDirectory" }
}

public protocol DownloadBucketTransferListener: Sendable {

    // DownloadBucket hooks.

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

    static var logger: DownloadBucketTransferListener {
        DownloadBucketLoggingTransferListener()
    }

    static var asyncStreaming: DownloadBucketTransferListener {
        DownloadBucketStreamingTransferListener()
    }

    var operation: String { "DownloadBucket" }
}
