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

    internal init(concurrerntTaskLimitPerBucket: Int) {
        self.concurrentTaskLimitPerBucket = concurrerntTaskLimitPerBucket
    }

    // Gets or creates a new BucketQueue for the specified bucket name.
    private func getQueue(forBucket bucketName: String) -> BucketQueue {
        if let existingQueue = bucketQueues[bucketName] {
            return existingQueue
        } else {
            let newBucketQueue = BucketQueue()
            bucketQueues[bucketName] = newBucketQueue
            return newBucketQueue
        }
    }

    internal func addContinuation(forBucket bucketName: String, continuation: CheckedContinuation<Void, Never>) {
        let queue = getQueue(forBucket: bucketName)
        queue.addWaitingTask(continuation)
        startNextTask(forBucket: bucketName)
    }

    internal func taskCompleted(forBucket bucketName: String) {
        guard let queue = bucketQueues[bucketName] else { return }
        // Free up task count.
        queue.decrementActiveTaskCount()
        if queue.isInactive {
            // Remove queue if it's inactive.
            bucketQueues.removeValue(forKey: bucketName)
        } else {
            // Start next awaiting task if available.
            startNextTask(forBucket: bucketName)
        }
    }

    private func startNextTask(forBucket bucketName: String) {
        let queue = getQueue(forBucket: bucketName)
        // Return if there's no awaiting task.
        guard queue.hasWaitingTasks else { return }

        // Resume next awaiting task if concurrency limit isn't reached yet.
        if queue.activeTaskCount < concurrentTaskLimitPerBucket {
            if let nextTask = queue.getNextWaitingTask() {
                queue.incrementActiveTaskCount()
                nextTask.resume()
            }
        }
    }
}

private class BucketQueue {
    // Queue of tasks awaiting execution.
    private(set) var waitingTasks: [CheckedContinuation<Void, Never>] = []
    // Count of number of active tasks running against the bucket.
    private(set) var activeTaskCount: Int = 0

    internal var hasWaitingTasks: Bool {
        return !waitingTasks.isEmpty
    }
    internal var isInactive: Bool { // True if there's neither active nor waiting tasks.
        return activeTaskCount == 0 && waitingTasks.isEmpty
    }

    internal func addWaitingTask(_ continuation: CheckedContinuation<Void, Never>) {
        waitingTasks.append(continuation)
    }

    internal func getNextWaitingTask() -> CheckedContinuation<Void, Never>? {
        guard !waitingTasks.isEmpty else { return nil }
        return waitingTasks.removeFirst()
    }

    internal func incrementActiveTaskCount() {
        activeTaskCount += 1
    }

    internal func decrementActiveTaskCount() {
        activeTaskCount = max(0, activeTaskCount - 1)
    }
}
