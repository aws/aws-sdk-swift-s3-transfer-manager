//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import class Foundation.FileHandle
import class Foundation.FileManager
import class SmithyStreams.FileStream
import enum Smithy.ByteStream
import struct Foundation.URL

public extension S3TransferManager {
    /// Uploads a local directory to an S3 bucket.
    ///
    /// Returns a `Task` immediately after function call; upload is handled in the background using asynchronous child tasks.
    /// If the `Task` returned by the function gets cancelled, all child tasks also get cancelled automatically.
    ///
    /// - Parameters:
    ///   - input: An instance of `UploadDirectoryInput`, the synthetic input type specific to this operation of `S3TransferManager`.
    /// - Returns: An asynchronous `Task<UploadDirectoryOutput, Error>` that can be optionally waited on or cancelled as needed.
    func uploadDirectory(input: UploadDirectoryInput) throws -> Task<UploadDirectoryOutput, Error> {
        return Task {
            let snapshot = DirectoryTransferProgressSnapshot(transferredFiles: 0, totalFiles: 0)
            input.directoryTransferListeners.forEach { $0.onTransferInitiated(input: input, snapshot: snapshot) }

            // Concurrency-safe storage for results of `uploadObject` child tasks.
            let results = Results()

            do {
                let nestedFileURLs = try getNestedFileURLs(
                    in: input.source,
                    recursive: input.recursive,
                    followSymbolicLinks: input.followSymbolicLinks
                )
                await withThrowingTaskGroup(of: Void.self) { group in
                    var uploadObjectOperationNum = 1
                    for url in nestedFileURLs {
                        // Need to capture specific operation number value for each task.
                        let operationNum = uploadObjectOperationNum
                        group.addTask {
                            return try await self.uploadObjectTask(input, operationNum, url, results)
                        }
                        uploadObjectOperationNum += 1
                    }
                }
                return await processResultsAndGetOutput(input: input, results: results)
            } catch {
                await processResultsBeforeThrowing(error: error, input: input, results: results)
                throw error
            }
        }
    }

    private func uploadObjectTask(
        _ input: UploadDirectoryInput,
        _ operationNum: Int,
        _ url: URL,
        _ results: Results
    ) async throws {
        do {
            try Task.checkCancellation()
            _ = try await self.uploadObjectFromURL(input, operationNum, url)
            await results.incrementSuccess()
        } catch {
            await results.incrementFail()
            // Call failure policy closure to handle `uploadObject` failure.
            // If this throws an error, all tasks within the throwing task group are cancelled automatically.
            try await input.failurePolicy(error, input)
        }
    }

    private func processResultsAndGetOutput(
        input: UploadDirectoryInput,
        results: Results
    ) async -> UploadDirectoryOutput {
        let (successfulUploadCount, failedUploadCount) = await results.getValues()
        let uploadDirectoryOutput = UploadDirectoryOutput(
            objectsUploaded: successfulUploadCount,
            objectsFailed: failedUploadCount
        )
        let snapshot = DirectoryTransferProgressSnapshot(
            transferredFiles: successfulUploadCount,
            totalFiles: successfulUploadCount + failedUploadCount
        )
        input.directoryTransferListeners.forEach { $0.onTransferComplete(
            input: input,
            output: uploadDirectoryOutput,
            snapshot: snapshot
        )}
        return uploadDirectoryOutput
    }

    private func processResultsBeforeThrowing(
        error: Error,
        input: UploadDirectoryInput,
        results: Results
    ) async {
        let (successfulUploadCount, failedUploadCount) = await results.getValues()
        let snapshot = DirectoryTransferProgressSnapshot(
            transferredFiles: successfulUploadCount,
            totalFiles: successfulUploadCount + failedUploadCount
        )
        input.directoryTransferListeners.forEach { $0.onTransferFailed(
            input: input,
            snapshot: snapshot,
            error: error
        )}
    }

    internal func getNestedFileURLs(
        in source: URL,
        recursive: Bool,
        followSymbolicLinks: Bool
    ) throws -> [URL] {
        var nestedFileURLs: [URL] = []
        var visitedURLs = Set<String>()

        // Mark source directory as visited.
        visitedURLs.insert(source.resolvingSymlinksInPath().absoluteString)

        // Start BFS with files directly nested below source directory.
        var bfsQueue = try getDirectlyNestedURLs(
            in: source,
            isSymlink: source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? false
        )

        // BFS for processing URLs contained in source directory.
        while !bfsQueue.isEmpty {
            let originalURL = bfsQueue.removeFirst()
            let originalURLProperties = try originalURL.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            )
            let originalURLIsSymlink = originalURLProperties.isSymbolicLink ?? false
            if originalURLIsSymlink && !followSymbolicLinks {
                continue
            }

            // URL without "./", "../", and symlinks.
            let resolvedURL = originalURL.resolvingSymlinksInPath()

            // Skip if current URL has already been looked at.
            if visitedURLs.contains(resolvedURL.absoluteString) {
                logger.debug("Skipping a duplicate URL: \(originalURL).")
                continue
            }

            // Add resolved URL to visited set.
            visitedURLs.insert(resolvedURL.absoluteString)

            let resolvedURLProperties = try resolvedURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey]
            )
            // If it's a directory URL & TM is configured to be recursive:
            if resolvedURLProperties.isDirectory ?? false && recursive {
                // Add subdirectory's directly nested file URLs to the BFS queue.
                let directlyNestedURLs = try getDirectlyNestedURLs(in: originalURL, isSymlink: originalURLIsSymlink)
                bfsQueue.append(contentsOf: directlyNestedURLs)
            } else if resolvedURLProperties.isRegularFile ?? false {
                // If it's a regular file, save it to the return value array.
                nestedFileURLs.append(originalURL)
            }
        }

        return nestedFileURLs
    }

    /*
        Note on logic:

        If originalDirURL is a symlink, we resolve it to get the resolvedDirURL because FileManager's contentsOfDirectory() doesn't work with symlink URL that points to a directory.

        Then we _swap out_ the base URLs (stuff before the last path component of directly nested file URLs) with the originalDirURL.

        Swapping base URL is done because we want to keep symlink names in the paths of nested URLs. For example, say we have the file structure below:
                |- dir
                    |- symlinkToDir2
                |- dir2
                    |- file.txt

        If dir/ is the source directory being uploaded and TM is configured to follow symlinks and subdirectories, we want file.txt to have the path "dir/symlinkToDir2/file.txt" (notice the name of symlink in path leading to file.txt), rather than "dir2/file.txt". That path ("dir/symlinkToDir2/file.txt") is then used to resolve the object key to upload the file with.
     */
    internal func getDirectlyNestedURLs(
        in originalDirURL: URL,
        isSymlink: Bool
    ) throws -> [URL] {
        // Resolve original directory URL if it's a symlink. `FileManager::contentsOfDirectory` doesn't accept symlinks.
        let resolvedDirURL = isSymlink ? originalDirURL.resolvingSymlinksInPath() : originalDirURL
        // Get file URLs (files, symlinks, directories, etc.) exactly one level below the provided directory URL.
        let directlyNestedURLs = try FileManager.default.contentsOfDirectory(
            at: resolvedDirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        return directlyNestedURLs.map {
            // Swap the base URL.
            URL(string: originalDirURL.absoluteString.appendingPathComponent($0.lastPathComponent))!
        }
    }

    private func uploadObjectFromURL(
        _ input: UploadDirectoryInput,
        _ operationNumber: Int,
        _ url: URL
    ) async throws {
        let resolvedObjectKey = try getResolvedObjectKey(of: url, inDir: input.source, input: input)

        var fileHandle: FileHandle
        do {
            fileHandle = try FileHandle.init(forReadingFrom: url)
        } catch {
            logger.debug("Could not read from URL: \(url.absoluteString), skipping.")
            return
        }

        defer { try? fileHandle.close() }

        let uploadObjectInput = input.uploadObjectRequestModifier(UploadObjectInput(
            id: input.id + "-\(operationNumber)",
            body: .stream(FileStream(fileHandle: fileHandle)),
            bucket: input.bucket,
            // CRC32 is SDK-default algorithm; this can be overwritten in callback by users.
            checksumAlgorithm: .crc32,
            key: resolvedObjectKey,
            transferListeners: await input.objectTransferListenerFactory()
        ))

        do {
            // Create S3TM `uploadObject` task and await its completion before returning.
            let uploadObjectTask = try uploadObject(input: uploadObjectInput)
            _ = try await uploadObjectTask.value
        } catch {
            // Upon failure, wrap the original error and the input in the synthetic error and throw.
            throw S3TMUploadDirectoryError.FailedToUploadAnObject(
                originalErrorFromUploadObject: error,
                failedUploadObjectInput: uploadObjectInput
            )
        }
    }

    internal func getResolvedObjectKey(of url: URL, inDir dir: URL, input: UploadDirectoryInput) throws -> String {
        // Step 1: if given a non-default s3Delimter, throw validation exception if the file name contains s3Delimiter.
        if input.s3Delimiter != defaultPathSeparator() && url.lastPathComponent.contains(input.s3Delimiter) {
            throw S3TMUploadDirectoryError.InvalidFileName(
                "The file \"\(url.absoluteString)\" has S3 delimiter \"\(input.s3Delimiter)\" in its name."
            )
        }
        // Step 2: append s3Delimiter to s3Prefix if it does not already end with it.
        var resolvedPrefix: String = ""
        if let providedPrefix = input.s3Prefix {
            resolvedPrefix = providedPrefix + (providedPrefix.hasSuffix(input.s3Delimiter) ? "" : input.s3Delimiter)
        }
        // Step 3: retrieve the relative path of the file URL.
        // Get absolute string of file URL & dir URL; remove dir URL prefix from file URL to get the relative path.
        var relativePath = url.absoluteString.removePrefix(dir.absoluteString).removePrefix(defaultPathSeparator())
        // Step 4: if user configured a custom s3Delimiter, replace all instances of system default path separator "/" in the relative path from step 3 with the custom s3Delimiter.
        if input.s3Delimiter != defaultPathSeparator() {
            relativePath = relativePath.replacingOccurrences(of: defaultPathSeparator(), with: input.s3Delimiter)
        }
        // Step 5: prefix the string from Step 4 with the resolved prefix.
        return resolvedPrefix + relativePath
    }
}

/// A non-exhaustive list of errors that can be thrown by the `uploadDirectory` operation of `S3TransferManager`.
public enum S3TMUploadDirectoryError: Error {
    case InvalidSourceURL(String)
    case FailedToUploadAnObject(
        originalErrorFromUploadObject: Error,
        failedUploadObjectInput: UploadObjectInput
    )
    case InvalidFileName(String)
}
