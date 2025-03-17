//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import class Foundation.DispatchQueue
import class Foundation.DispatchSemaphore
import struct Smithy.SwiftLogger

/// The Amazon S3 Transfer Manager for Swift, S3TM for short.
/// The S3TM is an out-of-the-box solution for performant and reliable uploads & downloads to and from AWS S3 buckets.
///
/// The S3TM supports the following features:
///  - Upload a single object to S3
///  - Download a single object from S3
///  - Upload a local directory to S3
///  - Download S3 bucket to a local directory
///  - Track transfer progress for all of the above
///
/// All operations return immediately with a `Task` that can be optionally waited on for the operation output.
///
/// For information on what options there are for each operation, go to the input type documentations (e.g., `UploadObjectInput`).
public class S3TransferManager {
    internal let config: S3TransferManagerConfig
    internal let logger: SwiftLogger
    internal let semaphoreManager: S3TMSemaphoreManager
    internal let concurrentTaskLimit: Int

    /// Initializes `S3TransferManager` with the default configuration.
    public init() async throws {
        self.config = try await S3TransferManagerConfig()
        self.concurrentTaskLimit = config.s3ClientConfig.httpClientConfiguration.maxConnections
        self.semaphoreManager = S3TMSemaphoreManager(concurrerntTaskLimit: concurrentTaskLimit)
        logger = SwiftLogger(label: "S3TransferManager")
    }

    /// Initializes `S3TransferManager` with the provided configuration.
    ///
    /// - Parameters:
    ///   - config: An instance of `S3TransferManagerConfig`.
    public init(
        config: S3TransferManagerConfig
    ) {
        self.config = config
        self.concurrentTaskLimit = config.s3ClientConfig.httpClientConfiguration.maxConnections
        self.semaphoreManager = S3TMSemaphoreManager(concurrerntTaskLimit: concurrentTaskLimit)
        logger = SwiftLogger(label: "S3TransferManager")
    }

    // MARK: - Miscellaneous helper functions.

    // Helper function used by `uploadDirectory` & `downloadBucket`.
    internal func defaultPathSeparator() -> String {
        return "/" // Default path separator for all apple platforms & Linux distros.
    }

    // Helper function that makes semaphore.wait() async.
    internal func wait(_ semaphore: DispatchSemaphore) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {  // Run on a separate GCD thread to prevent deadlock.
                semaphore.wait()
                continuation.resume()
            }
        }
    }

    // MARK: - 4 helper functions that call `TransferListener' hooks on an array of listeners.

    internal func onTransferInitiated(
        _ listeners: [TransferListener],
        _ input: TransferInput,
        _ snapshot: TransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onTransferInitiated(input: input, snapshot: snapshot)
        }
    }

    internal func onBytesTransferred(
        _ listeners: [TransferListener],
        _ input: TransferInput,
        _ snapshot: TransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onBytesTransferred(input: input, snapshot: snapshot)
        }
    }

    internal func onTransferComplete(
        _ listeners: [TransferListener],
        _ input: TransferInput,
        _ output: TransferOutput,
        _ snapshot: TransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onTransferComplete(input: input, output: output, snapshot: snapshot)
        }
    }

    internal func onTransferFailed(
        _ listeners: [TransferListener],
        _ input: TransferInput,
        _ snapshot: TransferProgressSnapshot
    ) {
        for listener in listeners {
            listener.onTransferFailed(input: input, snapshot: snapshot)
        }
    }
}
