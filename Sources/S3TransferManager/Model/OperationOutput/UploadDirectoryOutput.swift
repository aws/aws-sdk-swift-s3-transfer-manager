//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The synthetic output type for the `uploadDirectory` operation of `S3TransferManager`.
public struct UploadDirectoryOutput {
    /// The number of successfully uploaded objects.
    public let objectsUploaded: Int
    /// The number of failed uploads.
    public let objectsFailed: Int
}
