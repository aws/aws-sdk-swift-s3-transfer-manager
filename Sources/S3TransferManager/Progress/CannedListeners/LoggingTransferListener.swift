//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

@preconcurrency import struct Smithy.SwiftLogger

/// The `TransferListener` type that logs transfer status and progress using `swift-log`.
///
/// This transfer listener logs to the console by default.
///
/// See README.md for the example usage with the `uploadObject` transfer operation.
public struct LoggingTransferListener: TransferListener {
    private let logger = SwiftLogger(label: "LoggingTransferListener")

    /// Initializes `LoggingTransferListener`.
    public init() {}

    // Helper function that logs provided message with operation name & operation ID prefix.
    private func log(
        _ operation: String,
        _ operationID: String,
        _ message: String
    ) {
        logger.info("[\(operation) ID: \(operationID)] \(message)")
    }

    // MARK: - `uploadObject`.

    public func onUploadObjectTransferInitiated(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Resolved object key: \"\(input.putObjectInput.key!)\". "
        + "Destination bucket: \"\(input.putObjectInput.bucket!)\"."
        log("UploadObject", input.operationID, message)
    }

    public func onUploadObjectBytesTransferred(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = getProgressBarString(singleObjectSnapshot: snapshot)
        log("UploadObject", input.operationID, message)
    }

    public func onUploadObjectTransferComplete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred bytes: \(snapshot.transferredBytes)"
        log("UploadObject", input.operationID, message)
    }

    public func onUploadObjectTransferFailed(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        log("UploadObject", input.operationID, "Transfer failed.")
    }

    // MARK: - `downloadObject`.

    public func onDownloadObjectTransferInitiated(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Object key: \"\(input.getObjectInput.key!)\". "
        + "Source bucket: \"\(input.getObjectInput.bucket!)\"."
        log("DownloadObject", input.operationID, message)
    }

    public func onDownloadObjectBytesTransferred(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Downloaded more bytes. Running total: \(snapshot.transferredBytes)"
        log("DownloadObject", input.operationID, message)
    }

    public func onDownloadObjectTransferComplete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred bytes: \(snapshot.transferredBytes)"
        log("DownloadObject", input.operationID, message)
    }

    public func onDownloadObjectTransferFailed(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        log("DownloadObject", input.operationID, "Transfer failed.")
    }

    // MARK: - `uploadDirectory`.

    public func onUploadDirectoryTransferInitiated(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Source directory: \"\(input.source.path)\". "
        + "Destination bucket: \"\(input.bucket)\"."
        log("UploadDirectory", input.operationID, message)
    }

    public func onUploadDirectoryTransferComplete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred files: \(snapshot.transferredFiles)"
        log("UploadDirectory", input.operationID, message)
    }

    public func onUploadDirectoryTransferFailed(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        log("UploadDirectory", input.operationID, "Transfer failed.")
    }

    // MARK: - `downloadBucket`

    public func onDownloadBucketTransferInitiated(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Source bucket: \"\(input.bucket)\". "
        + "Destination directory: \"\(input.destination.path)\"."
        log("DownloadBucket", input.operationID, message)
    }

    public func onDownloadBucketTransferComplete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred files: \(snapshot.transferredFiles)"
        log("DownloadBucket", input.operationID, message)
    }

    public func onDownloadBucketTransferFailed(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        log("DownloadBucket", input.operationID, "Transfer failed.")
    }

    // Helper function that constructs progress bar string.
    private func getProgressBarString(singleObjectSnapshot: SingleObjectTransferProgressSnapshot) -> String {
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
