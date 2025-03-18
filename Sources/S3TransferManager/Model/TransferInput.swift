//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The parent protocol of all synthetic input types used with `S3TransferManager`.
public protocol TransferInput: Sendable {
    /// The unique ID for the operation; can be used to log or identify a specific request.
    var operationID: String { get }
}
