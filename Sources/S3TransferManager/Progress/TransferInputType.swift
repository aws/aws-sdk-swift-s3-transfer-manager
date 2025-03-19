//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

/// The enum that provides type-safe access to specific transfer operation inputs.
///
/// Instead of using explicit type casting with `as?`, this enum allows pattern matching to safely access concrete input types (e.g., `UploadObjectInput`) through its associated values:
///
/// ```
/// switch TransferInputType(from: input) {
/// case .uploadObject(let uploadInput):
///     // uploadInput is typed as UploadObjectInput
/// case .downloadObject(let downloadInput):
///     // downloadInput is typed as DownloadObjectInput
/// }
/// ```
public enum TransferInputType: CustomStringConvertible {
    case uploadObject(UploadObjectInput)
    case downloadObject(DownloadObjectInput)
    case uploadDirectory(UploadDirectoryInput)
    case downloadBucket(DownloadBucketInput)

    public init(from input: any TransferInput) {
        switch input {
        case let uploadInput as UploadObjectInput:
            self = .uploadObject(uploadInput)
        case let downloadInput as DownloadObjectInput:
            self = .downloadObject(downloadInput)
        case let uploadDirInput as UploadDirectoryInput:
            self = .uploadDirectory(uploadDirInput)
        case let downloadBucketInput as DownloadBucketInput:
            self = .downloadBucket(downloadBucketInput)
        default:
            fatalError("Unexpected TransferInput type: \(type(of: input))")
        }
    }

    // CustomStringConvertible conformance.
    public var description: String {
        switch self {
        case .uploadObject: return "UploadObject"
        case .downloadObject: return "DownloadObject"
        case .uploadDirectory: return "UploadDirectory"
        case .downloadBucket: return "DownloadBucket"
        }
    }
}
