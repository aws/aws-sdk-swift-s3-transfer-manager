//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest
import enum AWSS3.S3ClientTypes
import class Foundation.FileManager
@testable import S3TransferManager

class DownloadBucketUnitTests: S3TMUnitTestCase {


    // MARK: - validateOrCreateDestinationDirectory tests.

    func testValidateOrCreateDestinationDirectoryWithExistingDirectoryURL() throws {
        let resourcesDirectoryPath = DownloadBucketUnitTests.downloadBucketTestsResourcesURL.absoluteString
        let destinationURL = URL(string: resourcesDirectoryPath.appendingPathComponent(
            "destination"
        ))!
        try DownloadBucketUnitTests.tm.validateOrCreateDestinationDirectory(input: DownloadBucketInput(
            bucket: "dummy",
            destination: destinationURL
        ))
    }

    func testValidateOrCreateDestinationDirectoryWithExistingFileURL() throws {
        let resourcesDirectoryPath = DownloadBucketUnitTests.downloadBucketTestsResourcesURL.absoluteString
        let destinationURL = URL(string: resourcesDirectoryPath.appendingPathComponent(
            "file.txt"
        ))!
        do {
            try DownloadBucketUnitTests.tm.validateOrCreateDestinationDirectory(input: DownloadBucketInput(
                bucket: "dummy",
                destination: destinationURL
            ))
            XCTFail("Expected error S3TMDownloadBucketError.ProvidedDestinationIsNotADirectory to be thrown.")
        } catch S3TMDownloadBucketError.ProvidedDestinationIsNotADirectory {
            // Success; caught expected error. No-op.
        }
    }

    func testValidateOrCreateDestinationDirectoryCreatesDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString.split(separator: "-").first!.lowercased()
        let destinationURL = URL(string: tempDir.absoluteString.appendingPathComponent("\(uuid)/dir2/dir3"))!
        try DownloadBucketUnitTests.tm.validateOrCreateDestinationDirectory(input: DownloadBucketInput(
            bucket: "dummy",
            destination: destinationURL
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertTrue(try destinationURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false)
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("\(uuid)/"))
    }

    // MARK: - filePathEscapesDestination tests.

    func testFilePathEscapesDestinationFalse1() {
        let filePath = "a.txt"
        XCTAssertFalse(DownloadBucketUnitTests.tm.filePathEscapesDestination(filePath: filePath))
    }

    func testFilePathEscapesDestinationFalse2() {
        let filePath = "dir1/../dir2/../a.txt"
        XCTAssertFalse(DownloadBucketUnitTests.tm.filePathEscapesDestination(filePath: filePath))
    }

    func testFilePathEscapesDestinationFalse3() {
        let filePath = "dir1/dir2/../../dir3/a.txt"
        XCTAssertFalse(DownloadBucketUnitTests.tm.filePathEscapesDestination(filePath: filePath))
    }

    func testFilePathEscapesDestinationTrue1() {
        let filePath = "../a.txt"
        XCTAssertTrue(DownloadBucketUnitTests.tm.filePathEscapesDestination(filePath: filePath))
    }

    func testFilePathEscapesDestinationTrue2() {
        let filePath = "dir1/../../a.txt"
        XCTAssertTrue(DownloadBucketUnitTests.tm.filePathEscapesDestination(filePath: filePath))
    }

    func testFilePathEscapesDestinationTrue3() {
        let filePath = "dir1/dir2/../dir3/../../../a.txt"
        XCTAssertTrue(DownloadBucketUnitTests.tm.filePathEscapesDestination(filePath: filePath))
    }

    // MARK: - createFile tests.

    func testCreateFileWithTopLevelFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString.split(separator: "-").first!.lowercased()
        let fileURL = URL(string: tempDir.absoluteString.appendingPathComponent("\(uuid).txt"))!
        try DownloadBucketUnitTests.tm.createFile(at: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false)
        try FileManager.default.removeItem(at: fileURL)
    }

    func testCreateFileWithNestedFileCreatesIntermediateDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString.split(separator: "-").first!.lowercased()
        let fileURL = URL(string: tempDir.absoluteString.appendingPathComponent("\(uuid)/dir1/dir2/dir3/file.txt"))!
        try DownloadBucketUnitTests.tm.createFile(at: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false)
        try FileManager.default.removeItem(at: tempDir.appendingPathComponent("\(uuid)/"))
    }

    // MARK: - constructTempFileURL tests

    func testConstructTempFileURL() throws {
        let url = URL(fileURLWithPath: "/test/destination/file.txt")
        let tempURL = DownloadBucketUnitTests.tm.constructTempFileURL(originalURL: url)
        let filename = tempURL.deletingPathExtension().lastPathComponent
        let ext = tempURL.pathExtension
        XCTAssertTrue(filename.hasPrefix("file.s3tmp."))
        XCTAssertLessThanOrEqual(filename.replacingOccurrences(of: "file.s3tmp.", with: "").count, 8)
        XCTAssertEqual(ext, "txt")
    }

    // MARK: - deconstructTempFileURL tests

    func testDeconstructTempFileURL() throws {
        let original = URL(fileURLWithPath: "/test/destination/file.txt")
        let tempURL = DownloadBucketUnitTests.tm.constructTempFileURL(originalURL: original)
        let restored = DownloadBucketUnitTests.tm.deconstructTempFileURL(tempFileURL: tempURL)

        XCTAssertEqual(restored.path, original.path)
    }
}
