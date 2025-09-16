//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import S3TransferManager
@testable import TestUtil
import XCTest
import AWSS3

class DirectoryTransferIntegrationTests: XCTestCase {
    var tm: S3TransferManager!
    var testDatasetURL: URL!
    var downloadDestinationURL: URL!

    let region = "us-west-2"
    var bucketName: String!
    let bucketNamePrefix = "s3tm-directory-transfer-integ-test-"

    override func setUp() async throws {
        let s3ClientConfig = try await S3Client.S3ClientConfiguration(region: region)

        // Use smaller part sizes for GitHub Actions to test multipart behavior with smaller files
        let tmConfig: S3TransferManagerConfig
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
            tmConfig = try await S3TransferManagerConfig(
                s3ClientConfig: s3ClientConfig,
                targetPartSizeBytes: 2 * 1024 * 1024,  // 2MB
                multipartUploadThresholdBytes: 3 * 1024 * 1024  // 3MB
            )
        } else {
            tmConfig = try await S3TransferManagerConfig(s3ClientConfig: s3ClientConfig)
        }

        tm = S3TransferManager(config: tmConfig)

        let uuid = UUID().uuidString.split(separator: "-").first!.lowercased()
        bucketName = bucketNamePrefix + uuid

        // Create test dataset using script
        testDatasetURL = try createTestDatasetUsingScript()

        // Create download destination - use $HOME for local, temp for GitHub Actions
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

        // Assert exact number based on GitHub Actions vs local environment
        let expectedObjectCount = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" ? 70 : 315
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

        // Cleanup S3 bucket
        try await cleanupBucket(s3: s3)
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

        // Script creates dataset at location based on GitHub Actions vs local environment
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

        // Verify each file exists and has correct size
        for originalFile in originalFiles {
            let relativePath = originalFile.path.replacingOccurrences(of: testDatasetURL.path + "/", with: "")
            let downloadedFile = downloadDestinationURL.appendingPathComponent(relativePath)

            XCTAssertTrue(
                FileManager.default.fileExists(atPath: downloadedFile.path),
                "Downloaded file missing: \(relativePath)"
            )

            let originalSize = try originalFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let downloadedSize = try downloadedFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
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
