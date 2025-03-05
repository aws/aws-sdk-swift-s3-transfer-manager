//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import class Foundation.FileManager
import struct Foundation.Data
import struct Foundation.URL
import struct Foundation.UUID

/*
    Generates temporary resource directory below:
    |- DownloadBucketIntegTests-<uuid_fragment>
        |- source/
            |- nested/
                |- nested2/
                    |- nested3_1/
                        |- b.txt
                    |- nested3_2/
                        |- c.txt
                        |- d.txt
            |- a.txt
 */
internal func setUpDirectoryForDownloadBucketIntegTests() -> URL {
    do {
        let fm = FileManager.default
        let uuid = UUID().uuidString.split(separator: "-").first!.lowercased()
        let tempResourceDirectory = fm.temporaryDirectory.appendingPathComponent("DownloadBucketIntegTests-\(uuid)/")

        // Create directories.
        try fm.createDirectory(
            at: tempResourceDirectory.appendingPathComponent("source/nested/nested2/nested3_1/"),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: tempResourceDirectory.appendingPathComponent("source/nested/nested2/nested3_2/"),
            withIntermediateDirectories: true
        )

        // Create files.
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent(
                "source/a.txt"
            ).path,
            contents: Data("a".utf8)
        )
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent(
                "source/nested/nested2/nested3_1/b.txt"
            ).path,
            contents: Data("b".utf8)
        )
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent(
                "source/nested/nested2/nested3_2/c.txt"
            ).path,
            contents: Data("c".utf8)
        )
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent(
                "source/nested/nested2/nested3_2/d.txt"
            ).path,
            contents: Data("d".utf8)
        )

        return tempResourceDirectory.resolvingSymlinksInPath()
    } catch {
        fatalError("Failed to create the temporary resource directory for download bucket integration tests.")
    }
}
