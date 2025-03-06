//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

@testable import TestUtil
import XCTest

class UploadDirectoryTestSetupUtilTests: XCTestCase {
    var resourceDirectory: URL!

    override func setUp() async throws {
        resourceDirectory = setUpDirectoryForUploadDirectoryTests()
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: resourceDirectory)
    }

    func testUploadDirectoryTestSetup() {
        let fm = FileManager.default

        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent(
            "source/a.txt"
        ).path))
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent(
            "source/nested/b.txt"
        ).path))
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent(
            "outsideSource/c.txt"
        ).path))
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent(
            "source/nested/nested2/d.txt"
        ).path))
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent(
            "outsideSource/e.txt"
        ).path))
        XCTAssertTrue(fm.fileExists(atPath: resourceDirectory.appendingPathComponent(
            "f.txt"
        ).path))

        validateSymlink(
            symlinkPath: "outsideSource/symlinkToOutsideSourceDir",
            relativePathDestination: "../outsideSource"
        )
        validateSymlink(symlinkPath: "source/symlinkToFileF", relativePathDestination: "../f.txt")
        validateSymlink(symlinkPath: "source/symlinkToOutsideSourceDir", relativePathDestination: "../outsideSource")
        validateSymlink(symlinkPath: "source/symlinkToSourceDir", relativePathDestination: "../source")
    }

    private func validateSymlink(symlinkPath: String, relativePathDestination: String) {
        XCTAssertEqual(
            try? FileManager.default.destinationOfSymbolicLink(
                atPath: resourceDirectory.appendingPathComponent(symlinkPath).path
            ),
            relativePathDestination
        )
    }
}
