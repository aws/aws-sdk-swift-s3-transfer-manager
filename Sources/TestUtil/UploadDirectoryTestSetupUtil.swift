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
    |- UploadDirectoryTests-<uuid_fragment>
        |- source/
            |- nested/
                |- nested2/
                    |- d.txt
                |- b.txt
            |- a.txt
            |- symlinkToFileF
            |- symlinkToOutsideSourceDir
            |- symlinkToSourceDir
        |- outsideSource/
            |- c.txt
            |- e.txt
            |- symlinkToOutsideSourceDir
        |- f.txt
 */
internal func setUpDirectoryForUploadDirectoryTests() -> URL {
    do {
        let fm = FileManager.default
        let uuid = UUID().uuidString.split(separator: "-").first!.lowercased()
        let tempResourceDirectory = fm.temporaryDirectory.appendingPathComponent("UploadDirectoryTests-\(uuid)/")

        // Create directories.
        try fm.createDirectory(
            at: tempResourceDirectory.appendingPathComponent("outsideSource/"),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: tempResourceDirectory.appendingPathComponent("source/nested/nested2/"),
            withIntermediateDirectories: true
        )

        // Create files.
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent("source/a.txt").path,
            contents: Data("a".utf8)
        )
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent("source/nested/b.txt").path,
            contents: Data("b".utf8)
        )
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent("outsideSource/c.txt").path,
            contents: Data("c".utf8)
        )
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent("source/nested/nested2/d.txt").path,
            contents: Data("d".utf8)
        )
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent("outsideSource/e.txt").path,
            contents: Data("e".utf8)
        )
        fm.createFile(
            atPath: tempResourceDirectory.appendingPathComponent("f.txt").path,
            contents: Data("f".utf8)
        )

        // Create symlinks.
        try fm.createSymbolicLink(
            atPath: tempResourceDirectory.appendingPathComponent("outsideSource/symlinkToOutsideSourceDir").path,
            withDestinationPath: "../outsideSource"
        )
        try fm.createSymbolicLink(
            atPath: tempResourceDirectory.appendingPathComponent("source/symlinkToFileF").path,
            withDestinationPath: "../f.txt"
        )
        try fm.createSymbolicLink(
            atPath: tempResourceDirectory.appendingPathComponent("source/symlinkToOutsideSourceDir").path,
            withDestinationPath: "../outsideSource"
        )
        try fm.createSymbolicLink(
            atPath: tempResourceDirectory.appendingPathComponent("source/symlinkToSourceDir").path,
            withDestinationPath: "../source"
        )

        return tempResourceDirectory
    } catch {
        fatalError("Failed to create the temporary resource directory for upload directory tests.")
    }
}
