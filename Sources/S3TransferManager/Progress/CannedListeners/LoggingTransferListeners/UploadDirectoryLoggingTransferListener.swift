//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import protocol Smithy.LogAgent
import struct Smithy.SwiftLogger

/// The `TransferListener` type that logs transfer status and progress for `uploadDirectory` using `swift-log`.
///
/// This transfer listener logs to the console by default.
public struct UploadDirectoryLoggingTransferListener: UploadDirectoryTransferListener, ProgressLogger {
    let logger: LogAgent = SwiftLogger(label: "UploadDirectoryLoggingTransferListener")

    public init() {}

    public func onTransferInitiated(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Source directory: \"\(input.source.path)\". "
        + "Destination bucket: \"\(input.bucket)\"."
        log(input.id, message)
    }

    public func onTransferComplete(
        input: UploadDirectoryInput,
        output: UploadDirectoryOutput,
        snapshot: DirectoryTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred files: \(snapshot.transferredFiles)"
        log(input.id, message)
    }

    public func onTransferFailed(
        input: UploadDirectoryInput,
        snapshot: DirectoryTransferProgressSnapshot,
        error: Error
    ) {
        log(input.id, "Transfer failed with error: \(error)")
    }
}
