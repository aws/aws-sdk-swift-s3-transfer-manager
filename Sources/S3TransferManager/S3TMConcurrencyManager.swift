//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import struct Smithy.SwiftLogger

internal actor S3TMConcurrencyManager {
    // This value comes from the S3 client config's `httpClientConfiguration.maxConnections`.
    internal let concurrentTaskLimitPerBucket: Int

    // A dictionary that maps bucket names to their respective queue objects.
    private var bucketQueues: [String: BucketQueue] = [:]

    private let logger: SwiftLogger

    internal init(concurrentTaskLimitPerBucket: Int) {
        self.concurrentTaskLimitPerBucket = concurrentTaskLimitPerBucket
        self.logger = SwiftLogger(label: "S3TMConcurrencyManager")
    }

    // Gets or creates a new BucketQueue for the specified bucket name.
    private func getQueue(forBucket bucketName: String) -> BucketQueue {
        if let existingQueue = bucketQueues[bucketName] {
            return existingQueue
        } else {
            let newBucketQueue = BucketQueue(
                concurrentTaskLimit: concurrentTaskLimitPerBucket,
                logger: logger
            )
            bucketQueues[bucketName] = newBucketQueue
            return newBucketQueue
        }
    }

    internal func taskCompleted(forBucket bucketName: String) async {
        guard let queue = bucketQueues[bucketName] else { return }
        await queue.taskCompleted()
        if await queue.isInactive {
            // Remove queue if it's inactive.
            bucketQueues.removeValue(forKey: bucketName)
        }
    }

    internal func waitForPermission(bucketName: String) async {
        let queue = getQueue(forBucket: bucketName)
        await queue.waitForPermission()
    }
}

private actor BucketQueue {
    // Queue of continuations awaiting resume.
    var waitingContinuations: [CheckedContinuation<Void, Never>] = []

    // Count of number of active tasks running against the bucket.
    var activeTaskCount: Int = 0
    // The maximum number of concurrent tasks allowed for the bucket.
    private let concurrentTaskLimit: Int

    private let logger: SwiftLogger

    internal init(concurrentTaskLimit: Int, logger: SwiftLogger) {
        self.concurrentTaskLimit = concurrentTaskLimit
        self.logger = logger
    }

    internal var hasWaitingContinuations: Bool {
        return !waitingContinuations.isEmpty
    }

    internal var isInactive: Bool { // True if there's neither active tasks nor waiting continuations.
        return activeTaskCount == 0 && waitingContinuations.isEmpty
    }

    private func addContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        waitingContinuations.append(continuation)
        tryResumeNextContinuation()
    }

    internal func taskCompleted() {
        activeTaskCount -= 1
        assert(
            activeTaskCount > -1,
            "Running continuation count went below zero. "
            + "This should never happen."
        )
        tryResumeNextContinuation()
    }

    internal func waitForPermission() async {
        await withCheckedContinuation { continuation in
            addContinuation(continuation)
        }
    }

    private func tryResumeNextContinuation() {
        guard hasWaitingContinuations, activeTaskCount < concurrentTaskLimit else {
            logger.debug(
                "Unable to resume next continuation yet. "
                + "activeTaskCount: \(activeTaskCount) & hasWaitingContinuations: \(hasWaitingContinuations)."
            )
            return
        }

        let nextContinuation = waitingContinuations.removeFirst()
        activeTaskCount += 1
        nextContinuation.resume()
    }
}
