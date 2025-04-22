//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

internal actor S3TMConcurrencyManager {
    // This value comes from the S3 client config's `httpClientConfiguration.maxConnections`.
    internal let concurrentTaskLimitPerBucket: Int

    // A dictionary that maps bucket names to theier respective queue objects.
    private var bucketQueues: [String: BucketQueue] = [:]

    internal init(concurrentTaskLimitPerBucket: Int) {
        self.concurrentTaskLimitPerBucket = concurrentTaskLimitPerBucket
    }

    // Gets or creates a new BucketQueue for the specified bucket name.
    private func getQueue(forBucket bucketName: String) -> BucketQueue {
        if let existingQueue = bucketQueues[bucketName] {
            return existingQueue
        } else {
            let newBucketQueue = BucketQueue(concurrentTaskLimit: concurrentTaskLimitPerBucket)
            bucketQueues[bucketName] = newBucketQueue
            return newBucketQueue
        }
    }

    internal func addContinuation(forBucket bucketName: String, continuation: CheckedContinuation<Void, Never>) async {
        let queue = getQueue(forBucket: bucketName)
        await queue.addContinuation(continuation)
    }

    internal func taskCompleted(forBucket bucketName: String) async {
        guard let queue = bucketQueues[bucketName] else { return }
        let isInactive = await queue.taskCompleted()
        if isInactive {
            // Remove queue if it's inactive.
            bucketQueues.removeValue(forKey: bucketName)
        }
    }
}

private actor BucketQueue {
    // Queue of continuations awaiting resume.
    var waitingContinuations: [CheckedContinuation<Void, Never>] = []

    // Count of number of active tasks running against the bucket.
    var activeTaskCount: Int = 0
    // The maximum number of concurrent tasks allowed for the bucket.
    private let concurrentTaskLimit: Int

    internal init(concurrentTaskLimit: Int) {
        self.concurrentTaskLimit = concurrentTaskLimit
    }

    internal var hasWaitingContinuations: Bool {
        return !waitingContinuations.isEmpty
    }

    internal var isInactive: Bool { // True if there's neither active tasks nor waiting continuations.
        return activeTaskCount == 0 && waitingContinuations.isEmpty
    }

    internal func addContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        waitingContinuations.append(continuation)
        resumeNextContinuationIfPossible()
    }

    internal func taskCompleted() -> Bool {
        activeTaskCount -= 1
        assert(
            activeTaskCount > -1,
            "Running continuation count went below zero. "
            + "This should never happen."
        )
        resumeNextContinuationIfPossible()
        return isInactive
    }

    private func resumeNextContinuationIfPossible() {
        guard hasWaitingContinuations, activeTaskCount < concurrentTaskLimit else { return }

        let nextContinuation = waitingContinuations.removeFirst()
        activeTaskCount += 1
        nextContinuation.resume()
    }
}
