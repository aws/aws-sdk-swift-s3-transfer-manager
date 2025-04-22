//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
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
    internal let concurrencyManager: S3TMConcurrencyManager
    internal let concurrentTaskLimitPerBucket: Int

    /// Initializes `S3TransferManager` with the default configuration.
    public init() async throws {
        self.config = try await S3TransferManagerConfig()
        self.concurrentTaskLimitPerBucket = config.s3ClientConfig.httpClientConfiguration.maxConnections
        self.concurrencyManager = S3TMConcurrencyManager(concurrentTaskLimitPerBucket: concurrentTaskLimitPerBucket)
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
        self.concurrentTaskLimitPerBucket = config.s3ClientConfig.httpClientConfiguration.maxConnections
        self.concurrencyManager = S3TMConcurrencyManager(concurrentTaskLimitPerBucket: concurrentTaskLimitPerBucket)
        logger = SwiftLogger(label: "S3TransferManager")
    }
}

// MARK: - Collection of internal helper functions & actors.
internal extension S3TransferManager {
    // Helpers used by `uploadDirectory` & `downloadBucket`.

    func defaultPathSeparator() -> String {
        return "/" // Default path separator for all apple platforms & Linux distros.
    }

    actor Results {
        private var fail: Int = 0
        private var success: Int = 0

        func incrementFail() {
            fail += 1
        }

        func incrementSuccess() {
            success += 1
        }

        func getValues() -> (success: Int, fail: Int) {
            return (success, fail)
        }
    }

    // Helpers used for concurrency mgmt.

    private func taskCompleted(_ bucketName: String) async {
        await concurrencyManager.taskCompleted(forBucket: bucketName)
    }

    private func addContinuation(_ bucketName: String, _ continuation: CheckedContinuation<Void, Never>) async {
        await concurrencyManager.addContinuation(forBucket: bucketName, continuation: continuation)
    }

    private func waitForPermission(_ bucketName: String) async {
        await withCheckedContinuation { continuation in
            Task {
                await addContinuation(bucketName, continuation)
            }
        }
    }

    func withBucketPermission<T>(
        bucketName: String,
        operation: () async throws -> T
    ) async throws -> T {
        await waitForPermission(bucketName)

        do {
            let result = try await operation()
            await taskCompleted(bucketName)
            return result
        } catch {
            await taskCompleted(bucketName)
            throw error
        }
    }

    // An actor used to keep track of number of transferred bytes in single object transfer operations.
    actor ObjectTransferProgressTracker {
        var transferredBytes = 0

        // Adds newly transferred bytes & returns the new value.
        func addBytes(_ bytes: Int) -> Int {
            transferredBytes += bytes
            return transferredBytes
        }
    }
}
