//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

internal actor S3TMConcurrencyManager {
    // This value comes from the S3 client config's `httpClientConfiguration.maxConnections`.
    internal let concurrentTaskLimitPerBucket: Int

    // A dictionary that maps bucket names to a list of continuations, one continuation for each task.
    private var continuationsOnHoldPerBucket: [String: [CheckedContinuation<Void, Never>]] = [:]
    // A dictionary that maps bucket names to the current number of active tasks for that bucket.
    private var runningTaskCountPerBucket: [String: Int] = [:]

    internal init(concurrerntTaskLimitPerBucket: Int) {
        self.concurrentTaskLimitPerBucket = concurrerntTaskLimitPerBucket
    }

    internal func addContinuation(forBucket bucketName: String, continuation: CheckedContinuation<Void, Never>) {
        // Add new continuation to the waiting list of continuations for the bucket.
        if continuationsOnHoldPerBucket[bucketName] == nil {
            continuationsOnHoldPerBucket[bucketName] = []
        }
        continuationsOnHoldPerBucket[bucketName]?.append(continuation)

        // This resumes next-up continuation for the bucket if possible.
        startNextTask(forBucket: bucketName)
    }

    internal func taskCompleted(forBucket bucketName: String) async {
        // Decrement running task count for the bucket.
        if let currentRunningCount = runningTaskCountPerBucket[bucketName], currentRunningCount > 0 {
            runningTaskCountPerBucket[bucketName] = currentRunningCount - 1
        }

        // Remove count entry from running task count dictionary if there's no running task for the bucket.
        if runningTaskCountPerBucket[bucketName] == 0 {
            runningTaskCountPerBucket.removeValue(forKey: bucketName)
        }

        // This resumes next-up continuation for the bucket if possible.
        startNextTask(forBucket: bucketName)
    }

    private func startNextTask(forBucket bucketName: String) {
        // Remove entry from continuation dictionary if there's no continuation awaiting resume.
        guard var continuationsForBucket = continuationsOnHoldPerBucket[bucketName],
              !continuationsForBucket.isEmpty else {
            continuationsOnHoldPerBucket.removeValue(forKey: bucketName)
            return
        }

        // Resume next-up continuation for the bucket if there's room.
        let currentRunningTaskCountForBucket = runningTaskCountPerBucket[bucketName] ?? 0
        if currentRunningTaskCountForBucket < concurrentTaskLimitPerBucket {
            let continuation = continuationsForBucket.removeFirst()
            // Update the modified array in the dictionary.
            continuationsOnHoldPerBucket[bucketName] = continuationsForBucket
            runningTaskCountPerBucket[bucketName] = currentRunningTaskCountForBucket + 1
            continuation.resume()
        }
    }
}
