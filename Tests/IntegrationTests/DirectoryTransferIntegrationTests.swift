//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import Foundation
import S3TransferManager
@testable import TestUtil
import XCTest

#if os(macOS) || os(Linux)
class DirectoryTransferIntegrationTests: XCTestCase {
    var tm: S3TransferManager!
    var testDatasetURL: URL!
    var downloadDestinationURL: URL!

    let region = "us-west-2"
    var bucketName: String!
    let bucketNamePrefix = "s3tm-directory-transfer-integ-test-"

    override func setUp() async throws {
        let s3ClientConfig = try await S3Client.S3ClientConfiguration(region: region)
        let tmConfig = try await S3TransferManagerConfig(
            s3ClientConfig: s3ClientConfig,
            multipartUploadThresholdBytes: 10 * 1024 * 1024  // 10MB
        )
        tm = S3TransferManager(config: tmConfig)

        let uuid = UUID().uuidString.split(separator: "-").first!.lowercased()
        bucketName = bucketNamePrefix + uuid

        // Create test dataset using script
        testDatasetURL = try createTestDatasetUsingScript()

        // Create download destination - use temp for CI, home for local
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
            downloadDestinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                "directory-transfer-integ-test-\(uuid)"
            )
        } else {
            let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
            downloadDestinationURL = URL(fileURLWithPath: "\(homeDir)/directory-transfer-integ-test-\(uuid)")
        }
        try FileManager.default.createDirectory(at: downloadDestinationURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Cleanup S3 bucket if it exists
        if let bucketName = bucketName {
            let s3 = try S3Client(region: region)
            try? await cleanupBucket(s3: s3)
        }

        // Cleanup local directories
        if let testDatasetURL = testDatasetURL {
            try? FileManager.default.removeItem(at: testDatasetURL)
        }
        if let downloadDestinationURL = downloadDestinationURL {
            try? FileManager.default.removeItem(at: downloadDestinationURL)
        }
    }

    func testUploadAndDownloadNestedDataset() async throws {
        // Create S3 bucket
        let s3 = try S3Client(region: region)
        _ = try await s3.createBucket(input: CreateBucketInput(
            bucket: bucketName,
            createBucketConfiguration: S3ClientTypes.CreateBucketConfiguration(
                locationConstraint: S3ClientTypes.BucketLocationConstraint.usWest2
            )
        ))

        // Upload entire dataset
        let uploadInput = try UploadDirectoryInput(
            bucket: bucketName,
            source: testDatasetURL,
            recursive: true
        )

        let uploadTask = try tm.uploadDirectory(input: uploadInput)
        let uploadOutput = try await uploadTask.value

        let expectedObjectCount = 315
        XCTAssertEqual(uploadOutput.objectsUploaded, expectedObjectCount)
        XCTAssertEqual(uploadOutput.objectsFailed, 0)

        // Download entire dataset
        let downloadInput = DownloadBucketInput(
            bucket: bucketName,
            destination: downloadDestinationURL
        )

        let downloadTask = try tm.downloadBucket(input: downloadInput)
        let downloadOutput = try await downloadTask.value

        XCTAssertEqual(downloadOutput.objectsDownloaded, expectedObjectCount)
        XCTAssertEqual(downloadOutput.objectsFailed, 0)

        // Verify file structure and content
        try await verifyDatasetIntegrity()
    }

    private func createTestDatasetUsingScript() throws -> URL {
        let scriptPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/create_test_dataset.sh")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath.path]
        process.environment = ProcessInfo.processInfo.environment

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "TestSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Script failed"])
        }

        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
            let tempDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
            return URL(fileURLWithPath: "\(tempDir)/test_dataset")
        } else {
            let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
            return URL(fileURLWithPath: "\(homeDir)/test_dataset")
        }
    }

    private func verifyDatasetIntegrity() async throws {
        let originalFiles = getAllFiles(in: testDatasetURL)
        let downloadedFiles = getAllFiles(in: downloadDestinationURL)

        XCTAssertEqual(originalFiles.count, downloadedFiles.count, "File count mismatch")

        // Step 1: Get the base path components for both directories
        // Example: testDatasetURL = "/private/var/.../test_dataset" -> ["private", "var", ..., "test_dataset"]
        let sourceBaseComponents = testDatasetURL.pathComponents
        let destBaseComponents = downloadDestinationURL.pathComponents

        // Step 2: Create a lookup map of downloaded files by their relative path structure
        // This allows us to find downloaded files by their directory structure, not absolute paths
        var downloadedFileMap: [[String]: URL] = [:]

        for downloadedFile in downloadedFiles {
            // Get all path components: ["/", "var", "folders", ..., "download-dest", "department_1", "doc.dat"]
            let fullComponents = downloadedFile.pathComponents

            // Remove the base destination path to get relative structure
            // Example: ["department_1", "doc.dat"]
            let relativeComponents = Array(fullComponents.dropFirst(destBaseComponents.count))

            // Store in map: ["department_1", "doc.dat"] -> URL
            downloadedFileMap[relativeComponents] = downloadedFile
        }

        // Step 3: For each original file, find its matching downloaded file by structure
        for originalFile in originalFiles {
            // Get relative path components from original file
            let fullComponents = originalFile.pathComponents
            let relativeComponents = Array(fullComponents.dropFirst(sourceBaseComponents.count))

            // Look up the downloaded file with the same relative structure
            guard let downloadedFile = downloadedFileMap[relativeComponents] else {
                let relativePath = relativeComponents.joined(separator: "/")
                XCTFail("Downloaded file missing for relative path: \(relativePath)")
                continue
            }

            // Verify file sizes match
            let originalSize = try originalFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let downloadedSize = try downloadedFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let relativePath = relativeComponents.joined(separator: "/")
            XCTAssertEqual(originalSize, downloadedSize, "File size mismatch: \(relativePath)")
        }
    }

    private func getAllFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if let isRegularFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
               isRegularFile {
                files.append(fileURL)
            }
        }
        return files
    }

    private func cleanupBucket(s3: S3Client) async throws {
        // Check if bucket exists first
        do {
            _ = try await s3.headBucket(input: HeadBucketInput(bucket: bucketName))
        } catch {
            // Bucket doesn't exist, nothing to clean up
            return
        }

        // List and delete all objects
        let listOutput = try await s3.listObjectsV2(input: ListObjectsV2Input(bucket: bucketName))
        if let objects = listOutput.contents, !objects.isEmpty {
            let deleteObjects = objects.compactMap { $0.key }.map { S3ClientTypes.ObjectIdentifier(key: $0) }
            _ = try await s3.deleteObjects(input: DeleteObjectsInput(
                bucket: bucketName,
                delete: S3ClientTypes.Delete(objects: deleteObjects)
            ))
        }

        // Delete bucket
        _ = try await s3.deleteBucket(input: DeleteBucketInput(bucket: bucketName))
    }
}
#endif
