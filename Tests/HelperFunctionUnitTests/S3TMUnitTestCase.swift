//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

@testable import S3TransferManager
@testable import TestUtil
import XCTest

class S3TMUnitTestCase: XCTestCase {
    // The shared transfer manager for tests.
    static var tm: S3TransferManager!
    // The shared resources directory URL for download bucket unit tests.
    static var downloadBucketTestsResourcesURL: URL!
    // The shared resources directory URL for upload directory unit tests.
    static var uploadDirectoryTestsResourcesURL: URL!

    // class method setUp() runs only once, rather than for every test.
    override class func setUp() {
        let tmSetupExpectation = XCTestExpectation(description: "S3 Transfer Manager setup complete")
        Task {
            do {
                tm = try await S3TransferManager()
                tmSetupExpectation.fulfill()
            } catch {
                fatalError("Failed to set up S3 Transfer Manager: \(error)")
            }
        }
        _ = XCTWaiter().wait(for: [tmSetupExpectation], timeout: 5)
        downloadBucketTestsResourcesURL = setUpDirectoryForDownloadBucketUnitTests()
        uploadDirectoryTestsResourcesURL = setUpDirectoryForUploadDirectoryTests()
    }

    // delete the temporary resources directory after all tests are run in the test class.
    override class func tearDown() {
        do {
            try FileManager.default.removeItem(at: downloadBucketTestsResourcesURL)
            try FileManager.default.removeItem(at: uploadDirectoryTestsResourcesURL)
        } catch {
            XCTFail("Failed to delete temporary test resource directories: \(error)")
        }
    }

    // MARK: - Shared test utility functions.

    // Generates 0-filled temp file with specified MB size.
    func generateTempFile(sizeInMB: Int) throws -> URL {
        let fileName = UUID().uuidString.split(separator: "-").first!.lowercased() + ".txt"
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(fileName)
        let data = Data(count: sizeInMB * 1_024 * 1_024) // 1MB

        do {
            try data.write(to: tempFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
        }

        return tempFileURL
    }

    // Generates temp file with provided data.
    func generateTempFile(content: Data) throws -> URL {
        let fileName = UUID().uuidString.split(separator: "-").first!.lowercased() + ".txt"
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(fileName)

        do {
            try content.write(to: tempFileURL)
        } catch {
            XCTFail("Failed to create test file: \(error)")
        }

        return tempFileURL
    }

    func deleteTempFile(tempFileURL: URL) throws {
        if FileManager.default.fileExists(atPath: tempFileURL.path) {
            do {
                try FileManager.default.removeItem(at: tempFileURL)
            } catch {
                XCTFail("Failed to delete test file: \(error)")
            }
        }
    }
}
