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

// Imports the rename C-functino which atomically renames AND overwrites file if needed.
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

            // Concurrency-safe storage for results of `downloadObject` child tasks.
            let results = Results()

            var objectKeyToCreatedFileURLMap: [String: URL] = [:]
            do {
                objectKeyToCreatedFileURLMap = try await setupDestinations(input, config.s3Client)
                await withThrowingTaskGroup(of: Void.self) { group in
                    // Add `downloadObject` child tasks.
                    var downloadObjectOperationNum = 1
                    for pair in objectKeyToCreatedFileURLMap {
                        // Save current operation num as constant let.
                        // Using `downloadObjectOperationNum` directly in the group.addTask closure below results
                        //  in same value being used for the tasks bc var is a reference type & tasks get created
                        //  before they even start running. E.g., by the first task runs, `downloadObjectOperationNum`
                        //  could already be updated to its highest value.
                        let operationNum = downloadObjectOperationNum
                        group.addTask {
                            return try await self.downloadObjectTask(input, pair, operationNum, results)
                        }
                        downloadObjectOperationNum += 1
                    }
                }
                return await processResultsAndGetOutput(input, results)
            } catch {
                await processResultsBeforeThrowing(error, input, results)
                // Delete all temporary files.
                cleanupTempFilesBeforeThrowingError(
                    urls: objectKeyToCreatedFileURLMap.values.map { $0 }
                )
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

    private func setupDestinations(
        _ input: DownloadBucketInput,
        _ s3: S3Client
    ) async throws -> [String: URL] {
        try validateOrCreateDestinationDirectory(input: input)

        let objects = try await fetchS3ObjectsUsingListObjectsV2Paginated(input, s3)
        let objectKeyToResolvedFileURLMap: [String: URL] = getFileURLsResolvedFromObjectKeys(
            objects: objects,
            destination: input.destination,
            s3Prefix: input.s3Prefix,
            s3Delimiter: input.s3Delimiter,
            filter: input.filter
        )
        // Subset of `objectKeyToResolvedFileURLMap` above.
        // If resolved fileURL escapes the destination directory, it gets skipped.
        return try createDestinationFiles(
            keyToResolvedURLMapping: objectKeyToResolvedFileURLMap
        )
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

    private func fetchS3ObjectsUsingListObjectsV2Paginated(
        _ input: DownloadBucketInput,
        _ s3: S3Client
    ) async throws -> [S3ClientTypes.Object] {
        let bucketName = input.bucket

        return try await withBucketPermission(bucketName: bucketName) {
            var objects: [S3ClientTypes.Object] = []
            let paginatorOutputs = s3.listObjectsV2Paginated(input: ListObjectsV2Input(
                bucket: input.bucket,
                prefix: input.s3Prefix
            ))
            for try await output in paginatorOutputs {
                guard let contents = output.contents else {
                    throw S3TMDownloadBucketError.FailedToRetrieveObjectsUsingListObjectsV2
                }
                objects += contents
            }
            return objects
        }
    }

    internal func getFileURLsResolvedFromObjectKeys(
        objects: [S3ClientTypes.Object],
        destination: URL,
        s3Prefix: String? = nil,
        s3Delimiter: String,
        filter: (S3ClientTypes.Object) -> Bool
    ) -> [String: URL] {
        return Dictionary(uniqueKeysWithValues: objects.compactMap { object -> (String, URL)? in
            let originalKey = object.key!

            // Use user-provided filter to skip objects.
            // If key ends with delimiter, it's a 0-byte file used by S3 to simulate directory structure; skip that too.
            if !filter(object) || originalKey.hasSuffix(s3Delimiter) {
               return nil
            }

            let keyWithoutPrefix = originalKey.removePrefix(s3Prefix ?? "")

            // Replace instances of s3Delimiter in keyWithoutPrefix with Mac/Linux system default
            //      path separtor "/" if s3Delimiter isn't "/".
            // This effectively "translates" object key value to a file path.
            let relativeFilePath = s3Delimiter == defaultPathSeparator()
            ? keyWithoutPrefix
            : keyWithoutPrefix.replacingOccurrences(
                of: s3Delimiter,
                with: defaultPathSeparator()
            )

            // If relativeFilePath escapes destination directory, skip it.
            if filePathEscapesDestination(filePath: relativeFilePath) {
                return nil
            }

            // Return the mapping of original key to resolved file URL.
            return (originalKey, URL(string: destination.absoluteString.appendingPathComponent(relativeFilePath))!)
        })
    }

    internal func createDestinationFiles(
        keyToResolvedURLMapping: [String: URL]
    ) throws -> [String: URL] {
        var objectKeyToCreatedURLMapping: [String: URL] = [:]
        for pair in keyToResolvedURLMapping {
            let s3ObjectKey = pair.key
            let urlResolvedFromS3ObjKey = pair.value

            // Generate temp URL with `.s3tmp.<8-char-uniqueID` suffix in file name before type extension.
            var tempURLWithUniqueID = constructTempFileURL(originalURL: urlResolvedFromS3ObjKey)
            var tempDestinationPath = tempURLWithUniqueID.standardizedFileURL.path
            // Check & regenerate unique ID if a file already exists at destinationURL.
            while FileManager.default.fileExists(atPath: tempDestinationPath) {
                tempURLWithUniqueID = constructTempFileURL(originalURL: urlResolvedFromS3ObjKey)
                tempDestinationPath = tempURLWithUniqueID.standardizedFileURL.path
            }
            try createFile(at: URL(fileURLWithPath: tempDestinationPath))
            // Save the created file URL mapping.
            objectKeyToCreatedURLMapping[s3ObjectKey] = tempURLWithUniqueID
        }
        return objectKeyToCreatedURLMapping
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
        if let range = filename.range(of: ".s3tmp.") {
            let suffixStart = filename[range.upperBound...]
            if suffixStart.count <= 8 {
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
    ) {
        // Remove .s3tmp.<8-char-unique-ID> suffix from temp URL to finalize download.
        let result = wipURL.withUnsafeFileSystemRepresentation { wipFSR in
            finishedURL.withUnsafeFileSystemRepresentation { finishedFSR in
                return rename(wipFSR, finishedFSR)
            }
        }
        if result != 0 { // If rename failed:
            // Log the error before cleanup
            logger.debug(
                "Failed to rename \(wipURL.path) to \(finishedURL.path) for "
                + "DownloadObject call with operation ID \(operationID)."
            )
            // Attempt to delete the temporary file.
            try? FileManager.default.removeItem(at: wipURL)
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
        let downloadObjectInput = DownloadObjectInput(
            id: operationID,
            outputStream: outputStream,
            bucket: input.bucket,
            checksumMode: config.responseChecksumValidation == .whenSupported ? .enabled : .sdkUnknown("DISABLED"),
            key: pair.key,
            transferListeners: await input.objectTransferListenerFactory()
        )
        do {
            // Create S3TM `downloadObject` task and await its completion before returning.
            let downloadObjectTask = try downloadObject(input: downloadObjectInput)
            _ = try await downloadObjectTask.value
            // Finalize the file by removing the temporary suffix .s3tmp.<8-char-ID> from the filename in an atomic rename operation.
            atomicRenameWithOverwrite(
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
                logger.debug("Failed to delete temporary file at \(url): \(error)")
            }
        }
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
}
