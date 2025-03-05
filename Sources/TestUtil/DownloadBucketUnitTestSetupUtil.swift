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
    |- DownloadBucketUnitTests-<uuid_fragment>
        |- destination/
        |- file.txt
 */
internal func setUpDirectoryForDownloadBucketUnitTests() -> URL {
    do {
        let fm = FileManager.default
        let uuid = UUID().uuidString.split(separator: "-").first!.lowercased()
        let tempResourceDirectory = fm.temporaryDirectory.appendingPathComponent("DownloadBucketUnitTests-\(uuid)/")

        // Create directory.
        try fm.createDirectory(
            at: tempResourceDirectory.appendingPathComponent("destination/"),
            withIntermediateDirectories: true
        )

        // Create file.
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent("file.txt").path,
            contents: nil
        )

        return tempResourceDirectory.resolvingSymlinksInPath()
    } catch {
        fatalError("Failed to create the temporary resource directory for download bucket unit tests.")
    }
}
