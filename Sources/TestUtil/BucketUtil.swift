//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3

// Checks if a bucket with provided prefix exists in provided region.
// If it does exist, returns the full name of the bucket.
internal func bucketWithPrefixExists(prefix: String, region: String) async throws -> String? {
    let s3 = try S3Client(region: region)
    let listBucketsOutput = try await s3.listBuckets(input: ListBucketsInput(prefix: prefix))
    if let buckets = listBucketsOutput.buckets, buckets.count > 0 {
        return buckets[0].name
    } else {
        return nil
    }
}
