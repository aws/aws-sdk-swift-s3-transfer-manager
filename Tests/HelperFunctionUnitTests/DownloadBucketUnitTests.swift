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
    // MARK: - createDestinationFiles test.

    /*
        Create test directory with UUID in temp (notated with "p" below).
        Mappings used in the test:
        [
            "key1.txt" : URL with path p + key1.txt,
            "dir1/key2.txt" : URL with path p + dir1/key2.txt,
            "dir1/../key1.txt" : URL with path p + dir1/../key1.txt,
        ]
     */

    func testCreateDestinationFiles() throws {
        let uuid = UUID().uuidString.split(separator: "-").first!.lowercased()
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent(uuid, isDirectory: true)
        let keyToURLInput: [String: URL] = [
            "key1.txt": URL(string: testDir.absoluteString.appendingPathComponent("key1.txt"))!,
            "dir1/key2.txt": URL(string: testDir.absoluteString.appendingPathComponent("dir1/key2.txt"))!,
            "dir1/../key1.txt": URL(string: testDir.absoluteString.appendingPathComponent("dir1/../key1.txt"))!
        ]
        let actualKeyToCreatedURLsMap = try DownloadBucketUnitTests.tm.createDestinationFiles(
            keyToResolvedURLMapping: keyToURLInput
        )
        XCTAssertEqual(actualKeyToCreatedURLsMap.count, 3)
        try FileManager.default.removeItem(at: testDir)
    }

    // MARK: - getFileURLsResolvedFromObjectKeys tests.

    func testGetFileURLsResolvedFromObjectKeysWithCustomFilter() {
        let objects = s3ObjectsForGetFileURLsResolvedFromObjectKeysTests()
        let destination = URL(string: "dest/")!
        let objectKeyToResolvedURL = DownloadBucketUnitTests.tm.getFileURLsResolvedFromObjectKeys(
            objects: objects,
            destination: destination,
            s3Prefix: nil,
            filter: { object in return !object.key!.hasPrefix("dir1") }
        )
        let expectedMap: [String: URL] = [
            "a.txt": URL(string: "dest/a.txt")!,
            "dir3/d.txt": URL(string: "dest/dir3/d.txt")!
        ]
        XCTAssertEqual(objectKeyToResolvedURL, expectedMap)
    }

    func testGetFileURLsResolvedFromObjectKeysWithS3Prefix() {
        let prefix = "pre/"
        let objects = s3ObjectsForGetFileURLsResolvedFromObjectKeysTests(
            prefix: prefix
        )
        let destination = URL(string: "dest/")!
        let objectKeyToResolvedURL = DownloadBucketUnitTests.tm.getFileURLsResolvedFromObjectKeys(
            objects: objects,
            destination: destination,
            s3Prefix: prefix,
            filter: { object in return true }
        )
        let expectedMap: [String: URL] = [
            "pre/a.txt": URL(string: "dest/a.txt")!,
            "pre/dir1/b.txt": URL(string: "dest/dir1/b.txt")!,
            "pre/dir1/dir2/c.txt": URL(string: "dest/dir1/dir2/c.txt")!,
            "pre/dir3/d.txt": URL(string: "dest/dir3/d.txt")!,
        ]
        XCTAssertEqual(objectKeyToResolvedURL, expectedMap)
    }

    /*
         Helper function for getFileURLsResolvedFromObjectKeys tests.

         List of used keys:
         - simulatedDirectory/
         - dir1/dir2/../../../escapedFile.txt
         - a.txt
         - dir1/b.txt
         - dir1/dir2/c.txt
         - dir3/d.txt
     */
    private func s3ObjectsForGetFileURLsResolvedFromObjectKeysTests(
        prefix: String = ""
    ) -> [S3ClientTypes.Object] {
        let d = "/"
        return [
            .init(key: prefix + "simulatedDirectory\(d)"), // File skipped bc it ends with "/"
            // File below needs to be skipped bc it escapes dest.
            .init(key: prefix + "dir1\(d)dir2\(d)..\(d)..\(d)..\(d)escapedFile.txt"),
            .init(key: prefix + "a.txt"),
            .init(key: prefix + "dir1\(d)b.txt"),
            .init(key: prefix + "dir1\(d)dir2\(d)c.txt"),
            .init(key: prefix + "dir3\(d)d.txt")
        ]
    }

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
