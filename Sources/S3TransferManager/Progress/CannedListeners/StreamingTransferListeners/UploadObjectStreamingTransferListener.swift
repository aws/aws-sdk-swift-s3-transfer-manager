//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The `TransferListener` type that streams `uploadObject` transfer opration events to `AsyncThrowingStream` to allow asynchronous and customized event handling.
///
/// This transfer listener allows custom handling of each transfer event defined by the `UploadObjectTransferEvent` enum.
/// To use, first initialize an instance of the listener, and include it as one of the listeners in the input (i.e., `UploadObjectInput.transferListeners`).
/// Then, start up a `Task` that asynchronously consumes the events from the stream before invoking `uploadObject`.
/// After you're done with using the listener, you must explicitly close the underlying stream by calling `closeStream()` on it.
///
/// In the case of transfer failure, failure event is streamed before the stream is closed with an error.
public final class UploadObjectStreamingTransferListener: UploadObjectTransferListener {
    /// The async throwing stream that can be asynchronously iterated on to retrieve the published events from `uploadObject`.
    public let eventStream: AsyncThrowingStream<UploadObjectTransferEvent, Error>

    // The continuations used internally to send events to the streams.
    private let continuation: AsyncThrowingStream<UploadObjectTransferEvent, Error>.Continuation

    public init() {
        (self.eventStream, self.continuation) = AsyncThrowingStream.makeStream()
    }

    /// Closes the stream used by the `UploadObjectStreamingTransferListener` instance.
    public func closeStream() {
        continuation.finish()
    }

    public func onTransferInitiated(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        continuation.yield(
            UploadObjectTransferEvent.initiated(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onBytesTransferred(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        continuation.yield(
            UploadObjectTransferEvent.bytesTransferred(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onTransferComplete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        continuation.yield(
            UploadObjectTransferEvent.complete(
                input: input,
                output: output,
                snapshot: snapshot
            )
        )
    }

    public func onTransferFailed(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot,
        error: Error
    ) {
        continuation.yield(
            UploadObjectTransferEvent.failed(
                input: input,
                snapshot: snapshot
            )
        )
        continuation.finish(throwing: error)
    }
}

/// The set of events for `uploadObject` that `StreamingTransferListener` publishes to its corresponding stream instance property.
public enum UploadObjectTransferEvent: Sendable {
    case initiated(input: UploadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
    case bytesTransferred(input: UploadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
    case complete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    )
    case failed(input: UploadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
}
