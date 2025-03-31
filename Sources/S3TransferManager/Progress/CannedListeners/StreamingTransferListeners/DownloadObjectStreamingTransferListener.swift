//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The `TransferListener` type that streams `downloadObject` transfer opration events to `AsyncStream` to allow asynchronous and customized event handling.
///
/// This transfer listener allows custom handling of each transfer event defined by the `DownloadObjectTransferEvent` enum.
/// To use, first initialize an instance of the listener, and include it as one of the listeners in the input (i.e., `DownloadObjectInput.transferListeners`).
/// Then, start up a `Task` that asynchronously consumes the events from the stream before invoking `downloadObject`.
/// After you're done with using the listener, you must explicitly close the underlying stream by calling `closeStream()` on it.
public final class DownloadObjectStreamingTransferListener: DownloadObjectTransferListener {
    /// The async stream that can be asynchronously iterated on to retrieve the published events from `downloadObject`.
    public let eventStream: AsyncStream<DownloadObjectTransferEvent>

    // The continuations used internally to send events to the streams.
    private let continuation: AsyncStream<DownloadObjectTransferEvent>.Continuation

    public init() {
        (self.eventStream, self.continuation) = AsyncStream.makeStream()
    }

    /// Closes the stream used by the `DownloadObjectStreamingTransferListener` instance.
    public func closeStream() {
        continuation.finish()
    }

    public func onTransferInitiated(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        continuation.yield(
            DownloadObjectTransferEvent.initiated(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onBytesTransferred(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        continuation.yield(
            DownloadObjectTransferEvent.bytesTransferred(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onTransferComplete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        continuation.yield(
            DownloadObjectTransferEvent.complete(
                input: input,
                output: output,
                snapshot: snapshot
            )
        )
    }

    public func onTransferFailed(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        continuation.yield(
            DownloadObjectTransferEvent.failed(
                input: input,
                snapshot: snapshot
            )
        )
    }
}

/// The set of events for `downloadObject` that `StreamingTransferListener` publishes to its corresponding stream instance property.
public enum DownloadObjectTransferEvent: Sendable {
    case initiated(input: DownloadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
    case bytesTransferred(input: DownloadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
    case complete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    )
    case failed(input: DownloadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
}
