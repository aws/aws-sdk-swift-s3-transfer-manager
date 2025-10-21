//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
@testable import S3TransferManager
import Smithy
import XCTest

class DownloadObjectUnitTests: S3TMUnitTestCase {
    let dummyProgressTracker = S3TransferManager.ObjectTransferProgressTracker()

    func makeDummyInput(with stream: OutputStream) -> DownloadObjectInput {
        return DownloadObjectInput(
            outputStream: stream,
            bucket: "abc",
            key: "abc"
        )
    }

    // MARK: - writeData tests.

    func testWriteDataToFileOutputStream() async throws {
        // Create file output stream.
        let (fileOutputStream, tempFileURL) = try getEmptyFileOutputStream()

        // Write dummy data to file output stream.
        try await DownloadObjectUnitTests.tm.writeData(
            Data("abcdefg".utf8),
            makeDummyInput(with: fileOutputStream),
            dummyProgressTracker
        )

        // Assert on correct write.
        fileOutputStream.close()
        let writtenData = try Data(contentsOf: tempFileURL)
        let expectedData = Data("abcdefg".utf8)
        XCTAssertEqual(writtenData, expectedData)

        // Cleanup.
        try deleteTempFile(tempFileURL: tempFileURL)
    }

    func testWriteDataToMemoryOutputStream() async throws {
        // Create memory output stream.
        let memoryOutputStream = OutputStream.toMemory()

        // Write dummy data to memory output stream.
        try await DownloadObjectUnitTests.tm.writeData(
            Data("abcdefg".utf8),
            makeDummyInput(with: memoryOutputStream),
            dummyProgressTracker
        )

        // Assert on correct write.
        memoryOutputStream.close()
        let writtenData = memoryOutputStream.property(forKey: .dataWrittenToMemoryStreamKey) as! Data
        let expectedData = Data("abcdefg".utf8)
        XCTAssertEqual(writtenData, expectedData)
    }

    func testWriteDataToRawByteBufferOutputStream() async throws {
        // Create raw byte buffer output stream.
        let (rawByteBufferOutputStream, buffer) = try getEmptyRawByteBufferOutputStream(bufferCount: 7)

        // Write dummy data to raw byte buffer output stream.
        try await DownloadObjectUnitTests.tm.writeData(
            Data("abcdefg".utf8),
            makeDummyInput(with: rawByteBufferOutputStream),
            dummyProgressTracker
        )

        // Assert on correct write.
        rawByteBufferOutputStream.close()
        let writtenData = Data(buffer.prefix { $0 != 0 })
        let expectedData = Data("abcdefg".utf8)
        XCTAssertEqual(writtenData, expectedData)
    }

    // MARK: - Utility functions.

    private func getEmptyFileOutputStream() throws -> (OutputStream, tempFileURL: URL) {
        let tempFileURL = try generateTempFile(content: Data())
        let fileOutputStream = OutputStream(url: tempFileURL, append: true)!
        return (fileOutputStream, tempFileURL)
    }

    private func getEmptyRawByteBufferOutputStream(bufferCount: Int) throws -> (OutputStream, rawByteBuffer: [UInt8]) {
        var buffer = [UInt8](repeating: 0, count: bufferCount)
        let rawByteBufferOutputStream = OutputStream(toBuffer: &buffer, capacity: buffer.count)
        return (rawByteBufferOutputStream, buffer)
    }

    private func getDummyByteStream() -> ByteStream {
        return ByteStream.data(Data("0123456789abcde".utf8))
    }
}
