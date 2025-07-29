//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import protocol Smithy.LogAgent
import struct Smithy.SwiftLogger

/// The `TransferListener` type that logs transfer status and progress for `uploadObject` using `swift-log`.
///
/// This transfer listener logs to the console by default.
public struct UploadObjectLoggingTransferListener: UploadObjectTransferListener, ProgressLogger {
    let logger: LogAgent = SwiftLogger(label: "UploadObjectLoggingTransferListener")

    public init() {}

    public func onTransferInitiated(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer started. "
        + "Resolved object key: \"\(input.key)\". "
        + "Destination bucket: \"\(input.bucket)\"."
        log(input.id, message)
    }

    public func onBytesTransferred(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = getProgressBarString(singleObjectSnapshot: snapshot)
        log(input.id, message)
    }

    public func onTransferComplete(
        input: UploadObjectInput,
        output: UploadObjectOutput,
        snapshot: SingleObjectTransferProgressSnapshot
    ) {
        let message = "Transfer completed successfully. "
        + "Total number of transferred bytes: \(snapshot.transferredBytes)"
        log(input.id, message)
    }

    public func onTransferFailed(
        input: UploadObjectInput,
        snapshot: SingleObjectTransferProgressSnapshot,
        error: Error
    ) {
        log(input.id, "Transfer failed with error: \(error)")
    }

    // Helper function that constructs progress bar string for `uploadObject`.
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
