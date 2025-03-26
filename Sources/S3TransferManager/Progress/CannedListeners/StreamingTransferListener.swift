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
public final class StreamingTransferListener: TransferListener {
    /// The async stream that can be asynchronously iterated on to retrieve the published events from `uploadObject`.
    public let uploadObjectEventStream: AsyncThrowingStream<UploadObjectTransferEvent, Error>
    /// The async stream that can be asynchronously iterated on to retrieve the published events from `downloadObject`.
    public let downloadObjectEventStream: AsyncThrowingStream<DownloadObjectTransferEvent, Error>
    /// The async stream that can be asynchronously iterated on to retrieve the published events from `uploadDirectory`.
    public let uploadDirectoryEventStream: AsyncThrowingStream<UploadDirectoryTransferEvent, Error>
    /// The async stream that can be asynchronously iterated on to retrieve the published events from `downloadBucket`.
    public let downloadBucketEventStream: AsyncThrowingStream<DownloadBucketTransferEvent, Error>

    // swiftlint:disable line_length
    // The continuations used internally to send events to the streams.
    private let uploadObjectEventStreamContinuation: AsyncThrowingStream<UploadObjectTransferEvent, Error>.Continuation
    private let downloadObjectEventStreamContinuation: AsyncThrowingStream<DownloadObjectTransferEvent, Error>.Continuation
    private let uploadDirectoryEventStreamContinuation: AsyncThrowingStream<UploadDirectoryTransferEvent, Error>.Continuation
    private let downloadBucketEventStreamContinuation: AsyncThrowingStream<DownloadBucketTransferEvent, Error>.Continuation

    /// Initializes `StreamingTransferListener`.
    public init() {
        (self.uploadObjectEventStream, self.uploadObjectEventStreamContinuation) = AsyncThrowingStream.makeStream()
        (self.downloadObjectEventStream, self.downloadObjectEventStreamContinuation) = AsyncThrowingStream.makeStream()
        (self.uploadDirectoryEventStream, self.uploadDirectoryEventStreamContinuation) = AsyncThrowingStream.makeStream()
        (self.downloadBucketEventStream, self.downloadBucketEventStreamContinuation) = AsyncThrowingStream.makeStream()
    }
    // swiftlint:enable line_length

    /// Closes the streams used by the `StreamingTransferListener` instance.
    public func closeStreams() {
        uploadObjectEventStreamContinuation.finish()
        downloadObjectEventStreamContinuation.finish()
        uploadDirectoryEventStreamContinuation.finish()
        downloadBucketEventStreamContinuation.finish()
    }

    // MARK: - `uploadObject`.

    public func onUploadObjectTransferInitiated(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        uploadObjectEventStreamContinuation.yield(
            UploadObjectTransferEvent.uploadObjectInitiated(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onUploadObjectBytesTransferred(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        uploadObjectEventStreamContinuation.yield(
            UploadObjectTransferEvent.uploadObjectBytesTransferred(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onUploadObjectTransferComplete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        uploadObjectEventStreamContinuation.yield(
            UploadObjectTransferEvent.uploadObjectComplete(
                input: input,
                output: output,
                snapshot: snapshot
            )
        )
    }

    public func onUploadObjectTransferFailed(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        uploadObjectEventStreamContinuation.yield(
            UploadObjectTransferEvent.uploadObjectFailed(
                input: input,
                snapshot: snapshot
            )
        )
    }

    // MARK: - `downloadObject`.

    public func onDownloadObjectTransferInitiated(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        downloadObjectEventStreamContinuation.yield(
            DownloadObjectTransferEvent.downloadObjectInitiated(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onDownloadObjectBytesTransferred(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        downloadObjectEventStreamContinuation.yield(
            DownloadObjectTransferEvent.downloadObjectBytesTransferred(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onDownloadObjectTransferComplete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        downloadObjectEventStreamContinuation.yield(
            DownloadObjectTransferEvent.downloadObjectComplete(
                input: input,
                output: output,
                snapshot: snapshot
            )
        )
    }

    public func onDownloadObjectTransferFailed(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        downloadObjectEventStreamContinuation.yield(
            DownloadObjectTransferEvent.downloadObjectFailed(
                input: input,
                snapshot: snapshot
            )
        )
    }

    // MARK: - `uploadDirectory`.

    public func onUploadDirectoryTransferInitiated(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        uploadDirectoryEventStreamContinuation.yield(
            UploadDirectoryTransferEvent.uploadDirectoryInitiated(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onUploadDirectoryTransferComplete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        uploadDirectoryEventStreamContinuation.yield(
            UploadDirectoryTransferEvent.uploadDirectoryComplete(
                input: input,
                output: output,
                snapshot: snapshot
            )
        )
    }

    public func onUploadDirectoryTransferFailed(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        uploadDirectoryEventStreamContinuation.yield(
            UploadDirectoryTransferEvent.uploadDirectoryFailed(
                input: input,
                snapshot: snapshot
            )
        )
    }

    // MARK: - `downloadBucket`

    public func onDownloadBucketTransferInitiated(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        downloadBucketEventStreamContinuation.yield(
            DownloadBucketTransferEvent.downloadBucketInitiated(
                input: input,
                snapshot: snapshot
            )
        )
    }

    public func onDownloadBucketTransferComplete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        downloadBucketEventStreamContinuation.yield(
            DownloadBucketTransferEvent.downloadBucketComplete(
                input: input,
                output: output,
                snapshot: snapshot
            )
        )
    }

    public func onDownloadBucketTransferFailed(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot) {
            downloadBucketEventStreamContinuation.yield(
                DownloadBucketTransferEvent.downloadBucketFailed(
                    input: input,
                    snapshot: snapshot
                )
            )
    }
}

/// The set of events for `uploadObject` that `StreamingTransferListener` publishes to its corresponding stream instance property.
public enum UploadObjectTransferEvent: Sendable {
    case uploadObjectInitiated(input: UploadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
    case uploadObjectBytesTransferred(input: UploadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
    case uploadObjectComplete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    )
    case uploadObjectFailed(input: UploadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
}

/// The set of events for `downloadObject` that `StreamingTransferListener` publishes to its corresponding stream instance property.
public enum DownloadObjectTransferEvent: Sendable {
    case downloadObjectInitiated(input: DownloadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
    case downloadObjectBytesTransferred(input: DownloadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
    case downloadObjectComplete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    )
    case downloadObjectFailed(input: DownloadObjectInput, snapshot: SingleObjectTransferProgressSnapshot)
}

/// The set of events for `uploadDirectory` that `StreamingTransferListener` publishes to its corresponding stream instance property.
public enum UploadDirectoryTransferEvent: Sendable {
    case uploadDirectoryInitiated(input: UploadDirectoryInput, snapshot: DirectoryTransferProgressSnapshot)
    case uploadDirectoryComplete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    )
    case uploadDirectoryFailed(input: UploadDirectoryInput, snapshot: DirectoryTransferProgressSnapshot)
}

/// The set of events for `downloadBucket` that `StreamingTransferListener` publishes to its corresponding stream instance property.
public enum DownloadBucketTransferEvent: Sendable {
    case downloadBucketInitiated(input: DownloadBucketInput, snapshot: DirectoryTransferProgressSnapshot)
    case downloadBucketComplete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    )
    case downloadBucketFailed(input: DownloadBucketInput, snapshot: DirectoryTransferProgressSnapshot)
}
