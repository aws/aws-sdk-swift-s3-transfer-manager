//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import protocol Smithy.LogAgent
import struct Smithy.SwiftLogger

/// The `TransferListener` type that logs transfer status and progress for `downloadObject` using `swift-log`.
///
/// This transfer listener logs to the console by default.
public struct DownloadObjectLoggingTransferListener: DownloadObjectTransferListener, ProgressLogger {
    let logger: LogAgent = SwiftLogger(label: "DownloadObjectLoggingTransferListener")

    public init() {}

    public func onTransferInitiated(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Object key: \"\(input.getObjectInput.key!)\". "
        + "Source bucket: \"\(input.getObjectInput.bucket!)\"."
        log(input.id, message)
    }

    public func onBytesTransferred(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Downloaded more bytes. Running total: \(snapshot.transferredBytes)"
        log(input.id, message)
    }

    public func onTransferComplete(
        input: DownloadObjectInput,
        output: DownloadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred bytes: \(snapshot.transferredBytes)"
        log(input.id, message)
    }

    public func onTransferFailed(
        input: DownloadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        log(input.id, "Transfer failed.")
    }
}
