//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import TestUtil

class DownloadBucketIntegTestSetupUtilTests: XCTestCase {
    var resourceDirectory: URL!

    override func setUp() async throws {
        resourceDirectory = setUpDirectoryForDownloadBucketIntegTests()
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: resourceDirectory)
    }

    func testDownloadBucketIntegTestSetup() {
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent("source/a.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent(
            "source/nested/nested2/nested3_1/b.txt"
        ).path))
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent(
            "source/nested/nested2/nested3_2/c.txt"
        ).path))
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent(
            "source/nested/nested2/nested3_2/d.txt"
        ).path))
    }
}
