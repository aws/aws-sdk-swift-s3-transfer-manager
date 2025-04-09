//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import protocol Smithy.LogAgent
import struct Smithy.SwiftLogger

/// The `TransferListener` type that logs transfer status and progress for `downloadBucket` using `swift-log`.
///
/// This transfer listener logs to the console by default.
public struct DownloadBucketLoggingTransferListener: DownloadBucketTransferListener, ProgressLogger {
    let logger: LogAgent = SwiftLogger(label: "DownloadBucketLoggingTransferListener")

    public init() {}

    public func onTransferInitiated(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Source bucket: \"\(input.bucket)\". "
        + "Destination directory: \"\(input.destination.path)\"."
        log(input.id, message)
    }

    public func onTransferComplete(
        input: DownloadBucketInput,
        output: DownloadBucketOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred files: \(snapshot.transferredFiles)"
        log(input.id, message)
    }

    public func onTransferFailed(
        input: DownloadBucketInput,
        snapshot: DirectoryTransferProgressSnapshot,
        error: Error
    ) {
        log(input.id, "Transfer failed with error: \(error)")
    }
}
