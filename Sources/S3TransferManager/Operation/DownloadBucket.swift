//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import class Foundation.FileManager
import class Foundation.OutputStream
import struct Foundation.URL
import struct Foundation.UUID

// Imports the rename C-function which atomically renames AND overwrites file if needed.
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public extension S3TransferManager {
    /// Downloads S3 bucket to a local directory.
    ///
    /// Returns a `Task` immediately after function call; download is handled in the background using asynchronous child tasks.
    /// If the `Task` returned by the function gets cancelled, all child tasks also get cancelled automatically.
    ///
    /// - Parameters:
    ///   - input: An instance of `DownloadBucketInput`, the synthetic input type specific to this operation of `S3TransferManager`.
    /// - Returns: An asynchronous `Task<DownloadBucketOutput, Error>` that can be optionally waited on or cancelled as needed.
    func downloadBucket(input: DownloadBucketInput) throws -> Task<DownloadBucketOutput, Error> {
        return Task {
            input.directoryTransferListeners.forEach { $0.onTransferInitiated(
                input: input,
                snapshot: DirectoryTransferProgressSnapshot(transferredFiles: 0, totalFiles: 0)
            )}

            let results = Results()
            let downloadTracker = DownloadTracker()

            try validateOrCreateDestinationDirectory(input: input)

            let objectDiscovery = discoverObjectsProgressively(input: input)
            var createdTempFiles: [URL] = []

            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    var operationNum = 1
                    let maxConcurrentDownloads = input.maxConcurrency

                    for try await (objectKey, tempFileURL) in objectDiscovery {
                        createdTempFiles.append(tempFileURL)

                        // Wait if we've hit the concurrent downloadObject limit
                        while await downloadTracker.activeTransferCount >= maxConcurrentDownloads {
                            _ = try await group.next()
                        }

                        let currentOpNum = operationNum
                        await downloadTracker.increment()
                        group.addTask {
                            do {
                                try await self.downloadObjectTask(
                                    input, (objectKey, tempFileURL), currentOpNum, results
                                )
                                await downloadTracker.decrement()
                                return
                            } catch {
                                await downloadTracker.decrement()
                                throw error
                            }
                        }
                        operationNum += 1
                    }

                    // Wait for remaining downloads
                    while await downloadTracker.activeTransferCount > 0 {
                        _ = try await group.next()
                    }
                }
                return await processResultsAndGetOutput(input, results)
            } catch {
                await processResultsBeforeThrowing(error, input, results)
                cleanupTempFilesBeforeThrowingError(urls: createdTempFiles)
                throw error
            }
        }
    }

    private func downloadObjectTask(
        _ input: DownloadBucketInput,
        _ objectKeyToURL: (key: String, value: URL),
        _ operationNum: Int, // Used to construct child operation ID for listeners.
        _ results: Results
    ) async throws {
        do {
            try Task.checkCancellation()
            _ = try await self.downloadSingleObject(input, objectKeyToURL: objectKeyToURL, operationNum)
            await results.incrementSuccess()
        } catch {
            await results.incrementFail()
            // Call failure policy closure to handle `downloadObject` failure.
            // If this throws an error, all tasks within the throwing task group are cancelled automatically.
            try await input.failurePolicy(error, input)
        }
    }

    private func processResultsAndGetOutput(
        _ input: DownloadBucketInput,
        _ results: Results
    ) async -> DownloadBucketOutput {
        let (successfulDownloadCount, failedDownloadCount) = await results.getValues()
        let downloadBucketOutput = DownloadBucketOutput(
            objectsDownloaded: successfulDownloadCount,
            objectsFailed: failedDownloadCount
        )
        let snapshot = DirectoryTransferProgressSnapshot(
            transferredFiles: successfulDownloadCount,
            totalFiles: successfulDownloadCount + failedDownloadCount
        )
        input.directoryTransferListeners.forEach { $0.onTransferComplete(
            input: input,
            output: downloadBucketOutput,
            snapshot: snapshot
        )}
        return downloadBucketOutput
    }

    private func processResultsBeforeThrowing(
        _ error: Error,
        _ input: DownloadBucketInput,
        _ results: Results
    ) async {
        let (successfulDownloadCount, failedDownloadCount) = await results.getValues()
        let snapshot = DirectoryTransferProgressSnapshot(
            transferredFiles: successfulDownloadCount,
            totalFiles: successfulDownloadCount + failedDownloadCount
        )
        input.directoryTransferListeners.forEach {$0.onTransferFailed(
            input: input,
            snapshot: snapshot,
            error: error
        )}
    }

    internal func discoverObjectsProgressively(
        input: DownloadBucketInput
    ) -> AsyncThrowingStream<(String, URL), Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await withBucketPermission(bucketName: input.bucket) {
                        let paginatorOutputs = config.s3Client.listObjectsV2Paginated(input: ListObjectsV2Input(
                            bucket: input.bucket,
                            prefix: input.s3Prefix
                        ))

                        for try await output in paginatorOutputs {
                            guard let contents = output.contents else {
                                throw S3TMDownloadBucketError.FailedToRetrieveObjectsUsingListObjectsV2
                            }

                            for object in contents {
                                if let (objectKey, tempFileURL) = try processObject(object, input: input) {
                                    continuation.yield((objectKey, tempFileURL))
                                }
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.finish()
            }
        }
    }

    private func processObject(
        _ object: S3ClientTypes.Object,
        input: DownloadBucketInput
    ) throws -> (String, URL)? {
        let originalKey = object.key!
        let delimiter = "/"

        // Use user-provided filter to skip objects
        if !input.filter(object) || originalKey.hasSuffix(delimiter) {
            return nil
        }

        let relativeFilePath = originalKey.removePrefix(input.s3Prefix ?? "")

        // If relativeFilePath escapes destination directory, skip it
        if filePathEscapesDestination(filePath: relativeFilePath) {
            return nil
        }

        let resolvedFileURL = URL(string: input.destination.absoluteString.appendingPathComponent(relativeFilePath))!
        let tempFileURL = try createDestinationFile(originalURL: resolvedFileURL)

        return (originalKey, tempFileURL)
    }

    internal func validateOrCreateDestinationDirectory(
        input: DownloadBucketInput
    ) throws {
        if FileManager.default.fileExists(atPath: input.destination.path) {
            // Throw if destination exists but isn't a directory.
            guard try input.destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false else {
                throw S3TMDownloadBucketError.ProvidedDestinationIsNotADirectory
            }
        } else {
            // Create the destination directory if it's not present.
            do {
                try FileManager.default.createDirectory(at: input.destination, withIntermediateDirectories: true)
            } catch {
                throw S3TMDownloadBucketError.FailedToCreateDestinationDirectory
            }
        }
    }

    internal func createDestinationFile(originalURL: URL) throws -> URL {
        // Generate temp URL with `.s3tmp.<8-char-uniqueID` suffix in file name before type extension.
        var tempURLWithUniqueID = constructTempFileURL(originalURL: originalURL)
        var tempDestinationPath = tempURLWithUniqueID.standardizedFileURL.path
        // Check & regenerate unique ID if a file already exists at destinationURL.
        while FileManager.default.fileExists(atPath: tempDestinationPath) {
            tempURLWithUniqueID = constructTempFileURL(originalURL: originalURL)
            tempDestinationPath = tempURLWithUniqueID.standardizedFileURL.path
        }
        try createFile(at: URL(fileURLWithPath: tempDestinationPath))
        return tempURLWithUniqueID
    }

    internal func constructTempFileURL(originalURL: URL) -> URL {
        let directory = originalURL.deletingLastPathComponent()
        let filename = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension

        let uniqueSuffix = String(UUID().uuidString.prefix(8))
        let tempFilename = "\(filename).s3tmp.\(uniqueSuffix)"

        let finalFilename = ext.isEmpty ? tempFilename : "\(tempFilename).\(ext)"
        return directory.appendingPathComponent(finalFilename)
    }

    internal func deconstructTempFileURL(tempFileURL: URL) -> URL {
        let directory = tempFileURL.deletingLastPathComponent()
        let filename = tempFileURL.deletingPathExtension().lastPathComponent
        let ext = tempFileURL.pathExtension

        // Look for ".s3tmp." in the filename.
        if let range = filename.range(of: ".s3tmp.", options: .backwards) {
            let suffixStart = filename[range.upperBound...]
            if suffixStart.count == 8 {
                let baseFilename = String(filename[..<range.lowerBound])
                let finalFilename = ext.isEmpty ? baseFilename : "\(baseFilename).\(ext)"
                return directory.appendingPathComponent(finalFilename)
            }
        }

        // Not a temp file — return as is.
        return tempFileURL
    }

    func atomicRenameWithOverwrite(
        from wipURL: URL,
        to finishedURL: URL,
        operationID: String
    ) throws {
        // Remove .s3tmp.<8-char-unique-ID> suffix from temp URL to finalize download.
        let result = wipURL.withUnsafeFileSystemRepresentation { wipFSR in
            finishedURL.withUnsafeFileSystemRepresentation { finishedFSR in
                return rename(wipFSR, finishedFSR)
            }
        }
        if result != 0 { // If rename failed:
            // Log the error before cleanup
            logger.error(
                "Failed to rename \(wipURL.path) to \(finishedURL.path) for "
                + "DownloadObject call with operation ID \(operationID)."
            )
            // Attempt to delete the temporary file.
            try? FileManager.default.removeItem(at: wipURL)
            // Throw error; gets rethrown or hadled by failure policy.
            throw S3TMDownloadBucketError.FailedToRenameTemporaryFileAfterDownload(tempFile: wipURL)
        }
    }

    private func downloadSingleObject(
        _ input: DownloadBucketInput,
        objectKeyToURL pair: (key: String, value: URL),
        _ operationNumber: Int
    ) async throws {
        guard let outputStream = OutputStream(url: pair.value, append: true) else {
            throw S3TMDownloadBucketError.FailedToCreateOutputStreamForFileURL(url: pair.value)
        }
        let operationID = input.id + "-\(operationNumber)"
        let downloadObjectInput = input.downloadObjectRequestModifier(DownloadObjectInput(
            id: operationID,
            outputStream: outputStream,
            bucket: input.bucket,
            checksumMode: config.responseChecksumValidation == .whenSupported ? .enabled : .sdkUnknown("DISABLED"),
            key: pair.key,
            transferListeners: await input.objectTransferListenerFactory()
        ))
        do {
            // Create S3TM `downloadObject` task and await its completion before returning.
            let downloadObjectTask = try downloadObject(input: downloadObjectInput)
            _ = try await downloadObjectTask.value
            // Finalize the file by removing the temporary suffix .s3tmp.<8-char-ID> from the filename in an atomic rename operation.
            try atomicRenameWithOverwrite(
                from: pair.value,
                to: deconstructTempFileURL(tempFileURL: pair.value),
                operationID: operationID
            )
        } catch {
            // Upon failure, wrap the original error and the input in the synthetic error and throw.
            throw S3TMDownloadBucketError.FailedToDownloadAnObject(
                originalErrorFromDownloadObject: error,
                failedDownloadObjectInput: downloadObjectInput
            )
        }
    }

    internal func filePathEscapesDestination(filePath: String) -> Bool {
        let pathComponents = filePath.components(separatedBy: defaultPathSeparator())
        var nestedLevel = 0
        for component in pathComponents {
            if component == ".." {
                nestedLevel -= 1
            } else {
                nestedLevel += 1
            }
            // If at any point we go outside of destination directory (negative level), return true. It _could_ come back into destination directory, but we just return as soon as it escapes for simplicity.
            if nestedLevel < 0 {
                return true
            }
        }
        return false
    }

    internal func createFile(at url: URL) throws {
        let fileManager = FileManager.default

        // Get the directory path by deleting the last path component (the file name)
        let directoryURL = url.deletingLastPathComponent()

        do { // No-op if directory already exists.
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw S3TMDownloadBucketError.FailedToCreateNestedDestinationDirectory(at: directoryURL)
        }

        fileManager.createFile(atPath: url.path, contents: nil)
    }

    func cleanupTempFilesBeforeThrowingError(urls: [URL]) {
        let fileManager = FileManager.default
        for url in urls where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                logger.error("Failed to delete temporary file at \(url): \(error)")
            }
        }
    }
}

private actor DownloadTracker {
    private(set) var activeTransferCount = 0

    func increment() {
        activeTransferCount += 1
    }

    func decrement() {
        activeTransferCount -= 1
    }
}

/// A non-exhaustive list of errors that can be thrown by the `downloadBucket` operation of `S3TransferManager`.
public enum S3TMDownloadBucketError: Error {
    case ProvidedDestinationIsNotADirectory
    case FailedToCreateDestinationDirectory
    case FailedToRetrieveObjectsUsingListObjectsV2
    case FailedToCreateOutputStreamForFileURL(url: URL)
    case FailedToDownloadAnObject(
        originalErrorFromDownloadObject: Error,
        failedDownloadObjectInput: DownloadObjectInput
    )
    case FailedToCreateNestedDestinationDirectory(at: URL)
    case FailedToRenameTemporaryFileAfterDownload(tempFile: URL)
}
