//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import class Foundation.DispatchSemaphore

/*
    Manages the semaphores used by S3TM operation invocations.
    Each semaphore limits the number of concurrent tasks for a given bucket (endpoint host of the request).
    This prevents request timeouts by preventing child tasks that append requests to HTTP client (by calling S3 API of the underlying S3 client) from running in the first place if there's no capacity for making / using connections to a bucket.
    Because each child task only makes a single request with payload size smaller than or equal to `config.targetPartSizeBytes`, making use of built-in FIFO queue on semaphore waits & built-in request FIFO queue on HTTP client should work well enough to prevent request timeouts while still being performant.
 */
internal actor S3TMSemaphoreManager {
    // This value comes from the S3 client config value provided to S3TransferManagerConfig.
    internal var concurrentTaskLimit: Int
    // Map of each bucke name to a dedicated semaphore.
    private var semaphores: [String: SemaphoreInfo] = [:]

    internal init(concurrerntTaskLimit: Int) {
        self.concurrentTaskLimit = concurrerntTaskLimit
    }

    private struct SemaphoreInfo {
        let semaphore: DispatchSemaphore
        var useCount: Int
    }

    // Creates and/or returns the semaphore for a given bucket name.
    internal func getSemaphoreInstance(forBucket bucketName: String) -> DispatchSemaphore {
        if let info = semaphores[bucketName] {
            // Existing semaphore; increment usage count and return it.
            semaphores[bucketName] = SemaphoreInfo(
                semaphore: info.semaphore,
                useCount: info.useCount + 1
            )
            return info.semaphore
        } else {
            // Create new semaphore and return it.
            let newSemaphore = DispatchSemaphore(value: concurrentTaskLimit)
            semaphores[bucketName] = SemaphoreInfo(
                semaphore: newSemaphore,
                useCount: 1
            )
            return newSemaphore
        }
    }

    // Reduces usage count and/or deletes the semaphore for a given bucket name.
    internal func releaseSemaphoreInstance(forBucket bucketName: String) {
        guard let info = semaphores[bucketName] else { return }
        let newCount = info.useCount - 1
        if newCount <= 0 {
            // No more users, remove the semaphore.
            semaphores.removeValue(forKey: bucketName)
        } else {
            // Update use count.
            semaphores[bucketName] = SemaphoreInfo(
                semaphore: info.semaphore,
                useCount: newCount
            )
        }
    }
}
