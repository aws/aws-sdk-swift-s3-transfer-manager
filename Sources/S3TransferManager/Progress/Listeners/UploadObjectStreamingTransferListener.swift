//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The `TransferListener` type that streams operation specific events to operation specific`AsyncThrowingStream` to allow asynchronous and customized handling.
///
/// This transfer listener allows custom handling of each transfer event defined by the operation specific events defined by the enums `UploadObjectTransferEvent`, `DownloadObjectTransferEvent`, `UploadDirectoryTransferEvent`, and `DownloadBucketTransferEvent`.
/// To use, first initialize an instance of the listener, and include it as one of the listeners in the corresponding `S3TransferManger` operation's input (e.g., `UploadObjectInput.transferListeners`).
/// Then, start up a `Task` that asynchronously consumes the events from any of the streams before invoking the `S3TransferManager` operation.
/// After you're done with using the listener, you must explicitly close the underlying stream by calling `closeStreams()` on it.
///
/// See README.md for the example usage that consumes `uploadObject` operation's events.
public final class UploadObjectStreamingTransferListener: UploadObjectTransferListener {
    /// The async stream that can be asynchronously iterated on to retrieve the published events from `uploadObject`.
    public let eventStream: AsyncStream<UploadObjectTransferEvent>

    // The continuations used internally to send events to the streams.
    private let continuation: AsyncStream<UploadObjectTransferEvent>.Continuation

    /// Initializes `StreamingTransferListener`.
    public init() {
        (self.eventStream, self.continuation) = AsyncStream.makeStream()
    }

    /// Closes the streams used by the `StreamingTransferListener` instance.
    public func closeStreams() {
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
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        continuation.yield(
            UploadObjectTransferEvent.failed(
                input: input,
                snapshot: snapshot
            )
        )
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
