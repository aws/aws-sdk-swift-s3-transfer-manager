//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

@preconcurrency import protocol Smithy.LogAgent
@preconcurrency import struct Smithy.SwiftLogger

protocol ProgressLogger {
    var logger: LogAgent { get }
    var operation: String { get }
}

extension ProgressLogger {

    // Helper function that logs provided message with operation name & operation ID prefix.
    func log(
        _ operationID: String,
        _ message: String
    ) {
        logger.info("[\(operation) ID: \(operationID)] \(message)")
    }

    // Helper function that constructs progress bar string.
    func getProgressBarString(singleObjectSnapshot: SingleObjectTransferProgressSnapshot) -> String {
        // Example progress bar string: |==========          | 50.0%
        let barWidth = 20
        let totalBytes = Double(singleObjectSnapshot.totalBytes!)
        let ratio = totalBytes > 0
        ? (Double(singleObjectSnapshot.transferredBytes) / totalBytes)
        : 1
        // (X / 20) = (transferredBytes / totalBytes) where X is the number of "=" we want.
        let filledCount = Int(ratio * Double(barWidth))
        let emptyCount = barWidth - filledCount

        let filledSection = String(repeating: "=", count: filledCount)
        let emptySection = String(repeating: " ", count: emptyCount)
        let percentage = String(format: "%.1f", ratio * 100)
        return "|\(filledSection)\(emptySection)| \(percentage)%"
    }
}

/// The `TransferListener` type that logs transfer status and progress using `swift-log`.
///
/// This transfer listener logs to the console by default.
///
/// See README.md for the example usage with the `uploadObject` transfer operation.
public struct DownloadBucketLoggingTransferListener: DownloadBucketTransferListener, ProgressLogger {
    let logger: LogAgent = SwiftLogger(label: "LoggingTransferListener")

    /// Initializes `LoggingTransferListener`.
    public init() {}

    public func onTransferInitiated(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Source bucket: \"\(input.bucket)\". "
        + "Destination directory: \"\(input.destination.path)\"."
        log(input.operationID, message)
    }

    public func onTransferComplete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred files: \(snapshot.transferredFiles)"
        log(input.operationID, message)
    }

    public func onTransferFailed(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        log(input.operationID, "Transfer failed.")
    }
}

/// The `TransferListener` type that logs transfer status and progress using `swift-log`.
///
/// This transfer listener logs to the console by default.
///
/// See README.md for the example usage with the `uploadObject` transfer operation.
public struct DownloadObjectLoggingTransferListener: DownloadObjectTransferListener, ProgressLogger {
    let logger: LogAgent = SwiftLogger(label: "LoggingTransferListener")
    let operation = "DownloadObject"

    /// Initializes `LoggingTransferListener`.
    public init() {}

    public func onTransferInitiated(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Object key: \"\(input.getObjectInput.key!)\". "
        + "Source bucket: \"\(input.getObjectInput.bucket!)\"."
        log(input.operationID, message)
    }

    public func onBytesTransferred(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Downloaded more bytes. Running total: \(snapshot.transferredBytes)"
        log(input.operationID, message)
    }

    public func onTransferComplete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred bytes: \(snapshot.transferredBytes)"
        log(input.operationID, message)
    }

    public func onTransferFailed(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        log(input.operationID, "Transfer failed.")
    }
}

/// The `TransferListener` type that logs transfer status and progress using `swift-log`.
///
/// This transfer listener logs to the console by default.
///
/// See README.md for the example usage with the `uploadObject` transfer operation.
public struct UploadDirectoryLoggingTransferListener: UploadDirectoryTransferListener, ProgressLogger {
    let logger: LogAgent = SwiftLogger(label: "LoggingTransferListener")
    let operation = "UploadDirectory"

    /// Initializes `LoggingTransferListener`.
    public init() {}

    public func onTransferInitiated(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Source directory: \"\(input.source.path)\". "
        + "Destination bucket: \"\(input.bucket)\"."
        log(input.operationID, message)
    }

    public func onTransferComplete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred files: \(snapshot.transferredFiles)"
        log(input.operationID, message)
    }

    public func onTransferFailed(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        log(input.operationID, "Transfer failed.")
    }
}

/// The `TransferListener` type that logs transfer status and progress using `swift-log`.
///
/// This transfer listener logs to the console by default.
///
/// See README.md for the example usage with the `uploadObject` transfer operation.
public struct UploadObjectLoggingTransferListener: UploadObjectTransferListener, ProgressLogger {
    let logger: LogAgent = SwiftLogger(label: "LoggingTransferListener")
    let operation = "UploadObject"

    /// Initializes `LoggingTransferListener`.
    public init() {}

    public func onTransferInitiated(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Resolved object key: \"\(input.putObjectInput.key!)\". "
        + "Destination bucket: \"\(input.putObjectInput.bucket!)\"."
        log(input.operationID, message)
    }

    public func onBytesTransferred(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = getProgressBarString(singleObjectSnapshot: snapshot)
        log(input.operationID, message)
    }

    public func onTransferComplete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred bytes: \(snapshot.transferredBytes)"
        log(input.operationID, message)
    }

    public func onTransferFailed(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        log(input.operationID, "Transfer failed.")
    }
}
