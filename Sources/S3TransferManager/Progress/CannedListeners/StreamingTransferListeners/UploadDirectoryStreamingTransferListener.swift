//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The `TransferListener` type that streams `uploadDirectory` transfer opration events to `AsyncThrowingStream` to allow asynchronous and customized event handling.
///
/// This transfer listener allows custom handling of each transfer event defined by the `UploadDirectoryTransferEvent` enum.
/// To use, first initialize an instance of the listener, and include it as one of the listeners in the input (i.e., `UploadDirectoryInput.transferListeners`).
/// Then, start up a `Task` that asynchronously consumes the events from the stream before invoking `uploadDirectory`.
/// After you're done with using the listener, you must explicitly close the underlying stream by calling `closeStream()` on it.
///
/// In the case of transfer failure, failure event is streamed before the stream is closed with an error.
public final class UploadDirectoryStreamingTransferListener: UploadDirectoryTransferListener {
    /// The async throwing stream that can be asynchronously iterated on to retrieve the published events from `uploadDirectory`.
    public let eventStream: AsyncThrowingStream<UploadDirectoryTransferEvent, Error>

    // The continuations used internally to send events to the streams.
    private let continuation: AsyncThrowingStream<UploadDirectoryTransferEvent, Error>.Continuation

    public init() {
        (self.eventStream, self.continuation) = AsyncThrowingStream.makeStream()
    }

    /// Closes the stream used by the `UploadDirectoryStreamingTransferListener` instance.
    public func closeStream() {
        continuation.finish()
    }

    public func onTransferInitiated(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        continuation.yield(
            UploadDirectoryTransferEvent.initiated(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onTransferComplete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        continuation.yield(
            UploadDirectoryTransferEvent.complete(
                input: input,
                output: output,
                snapshot: snapshot
            )
        )
    }

    public func onTransferFailed(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot,
        error: Error
    ) {
        continuation.yield(
            UploadDirectoryTransferEvent.failed(
                input: input,
                snapshot: snapshot
            )
        )
        continuation.finish(throwing: error)
    }
}

/// The set of events for `uploadDirectory` that `StreamingTransferListener` publishes to its corresponding stream instance property.
public enum UploadDirectoryTransferEvent: Sendable {
    case initiated(input: UploadDirectoryInput, snapshot: DirectoryTransferProgressSnapshot)
    case complete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    )
    case failed(input: UploadDirectoryInput, snapshot: DirectoryTransferProgressSnapshot)
}
