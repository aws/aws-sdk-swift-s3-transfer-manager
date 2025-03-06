//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3

internal func bucketWithPrefixExists(prefix: String, region: String) async throws -> Bool {
    let s3 = try S3Client(region: region)
    let listBucketsOutput = try await s3.listBuckets(input: ListBucketsInput(prefix: prefix))
    if let buckets = listBucketsOutput.buckets {
        return buckets.count > 0
    } else {
        return false
    }
}
