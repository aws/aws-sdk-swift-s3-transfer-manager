//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import TestUtil

class DownloadBucketUnitTestSetupUtilTests: XCTestCase {
    var resourceDirectory: URL!

    override func setUp() async throws {
        resourceDirectory = setUpDirectoryForDownloadBucketUnitTests()
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: resourceDirectory)
    }

    func testDownloadBucketUnitTestSetup() {
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent("file.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent("destination/").path))
    }
}
