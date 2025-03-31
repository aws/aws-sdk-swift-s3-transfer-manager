//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The `TransferListener` type that streams `downloadBucket` transfer opration events to `AsyncStream` to allow asynchronous and customized event handling.
///
/// This transfer listener allows custom handling of each transfer event defined by the `DownloadBucketTransferEvent` enum.
/// To use, first initialize an instance of the listener, and include it as one of the listeners in the input (i.e., `DownloadBucketInput.transferListeners`).
/// Then, start up a `Task` that asynchronously consumes the events from the stream before invoking `downloadBucket`.
/// After you're done with using the listener, you must explicitly close the underlying stream by calling `closeStream()` on it.
public final class DownloadBucketStreamingTransferListener: DownloadBucketTransferListener {
    /// The async stream that can be asynchronously iterated on to retrieve the published events from `downloadBucket`.
    public let eventStream: AsyncStream<DownloadBucketTransferEvent>

    // The continuations used internally to send events to the streams.
    private let continuation: AsyncStream<DownloadBucketTransferEvent>.Continuation

    public init() {
        (self.eventStream, self.continuation) = AsyncStream.makeStream()
    }

    /// Closes the stream used by the `DownloadBucketStreamingTransferListener` instance.
    public func closeStream() {
        continuation.finish()
    }

    public func onTransferInitiated(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        continuation.yield(
            DownloadBucketTransferEvent.initiated(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onTransferComplete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        continuation.yield(
            DownloadBucketTransferEvent.complete(
                input: input,
                output: output,
                snapshot: snapshot
            )
        )
    }

    public func onTransferFailed(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        continuation.yield(
            DownloadBucketTransferEvent.failed(
                input: input,
                snapshot: snapshot
            )
        )
    }
}

/// The set of events for `downloadBucket` that `StreamingTransferListener` publishes to its corresponding stream instance property.
public enum DownloadBucketTransferEvent: Sendable {
    case initiated(input: DownloadBucketInput, snapshot: DirectoryTransferProgressSnapshot)
    case complete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    )
    case failed(input: DownloadBucketInput, snapshot: DirectoryTransferProgressSnapshot)
}
