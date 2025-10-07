//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSClientRuntime
import AWSS3
import AWSSDKChecksums
import ClientRuntime
import SmithyHTTPAPI

/// The config object for `S3TransferManager`.
public class S3TransferManagerConfig {
    // The underlying S3 client to which all operations will be routed to by TM.
    internal let s3Client: S3Client
    /// The S3 client config used to instantiate the S3 client `S3TransferManager` will use to make requests.
    let s3ClientConfig: S3Client.S3ClientConfiguration
    /// The part size used by multipart transfer operations. I.e., determines part size when uploading a file to an S3 bucket that exceed `multipartUploadThresholdBytes`, or when downloading an S3 object from an S3 bucket that exceed `targetPartSizeBytes`.
    let targetPartSizeBytes: Int
    /// The threshold for multipart uploads. All files bigger than this threshold will be uploaded using S3's multipart upload API.
    let multipartUploadThresholdBytes: Int
    /// Specifies when a checksum will be calculated for request. This takes precendence over the value in `s3ClientConfig`.
    let requestChecksumCalculation: AWSChecksumCalculationMode
    /// Specifies when a checksum validation will be performed on response. This takes precendence over the value in `s3ClientConfig`.
    let responseChecksumValidation: AWSChecksumCalculationMode
    /// The multipart download type to use for the `downloadObject` and `downloadBucket` operations.
    let multipartDownloadType: MultipartDownloadType
    /// The maximum number of bytes of parts held in memory for the S3TransferManager instance.
    let maxInMemoryBytes: Int

    /// Initializes `S3TransferManagerConfig` with provided parameters.
    ///
    /// - Parameters:
    ///    - s3ClientConfig: The S3 client config instance used to instantiate the S3 client used by the transfer manager. If not provided, a default S3 client config is used to create the underlying S3 client.
    ///    - targetPartSizeBytes: The part size used by multipart operations. The last part can be smaller. Default value is 8MB.
    ///    - multipartUploadThresholdBytes: The threshold at which multipart operations get used instead of a single `putObject` for the `uploadObject` operation. Default value is 16MB.
    ///    - requestChecksumCalculation: Specifies when checksum should be calculated for requests (e.g., upload operations). This value overrides the value provided in `s3ClientConfig`. Default value is `.whenSupported`, which means transfer manager will automatically calculate checksum in absence of full object checksum in operation input.
    ///    - responseChecksumValidation: Specifies when checksm should be validated for responses (e.g., download operations). This value overrides the value provided in `s3ClientConfig`. Default value is `.whenSupported`, which means transfer manager will automatically calculate checksum and validate it against checksum returned in the response.
    ///    - multipartDownloadType: Specifies the behavior of multipart download operations. Default value is `.part`, which configures individual `getObject` calls to use part numbers for multipart downloads. The other option is `.range`, which uses the byte range of the S3 object for multipart downloads. If what you want to download was uploaded without using multipart upload (therefore there's no part number available), then you should use `.range`.
    ///    - maxInMemoryBytes: Specifies the maximum number of bytes of parts held in memory for the S3TransferManager instance. Default vaule is 6GB for macOS and Linux, 1GB for iOS and tvOS, and 100MB for watchOS. Note that acutal memory usage of S3TransferManager instance can be greater, as this value only limits number of bytes held in memory during upload and download.
    public init(
        s3ClientConfig: S3Client.S3ClientConfiguration? = nil,
        targetPartSizeBytes: Int = 8 * 1024 * 1024,
        multipartUploadThresholdBytes: Int = 16 * 1024 * 1024,
        requestChecksumCalculation: AWSChecksumCalculationMode = .whenSupported,
        responseChecksumValidation: AWSChecksumCalculationMode = .whenSupported,
        multipartDownloadType: MultipartDownloadType = .part,
        maxInMemoryBytes: Int? = nil
    ) async throws {
        // If no client config was provided, initialize a default client config.
        if let s3ClientConfig {
            self.s3ClientConfig = s3ClientConfig
        } else {
            self.s3ClientConfig = try await S3Client.S3ClientConfiguration()
        }
        // Override checksum behavior configurations in passed in `s3ClientConfig` with
        //  checksum behavior configurations passed directly to TM.
        self.s3ClientConfig.requestChecksumCalculation = requestChecksumCalculation
        self.s3ClientConfig.responseChecksumValidation = responseChecksumValidation

        // Add intercpetor that injects [S3_TRANSFER : G] feature ID to requests.
        self.s3ClientConfig.addInterceptorProvider(_S3TransferManagerInterceptorProvider())

        // Instantiate the shared S3 client instance.
        self.s3Client = S3Client(config: self.s3ClientConfig)

        self.targetPartSizeBytes = targetPartSizeBytes
        self.multipartUploadThresholdBytes = multipartUploadThresholdBytes
        self.requestChecksumCalculation = requestChecksumCalculation
        self.responseChecksumValidation = responseChecksumValidation
        self.multipartDownloadType = multipartDownloadType
        self.maxInMemoryBytes = maxInMemoryBytes ?? {
        #if os(macOS) || os(Linux)
            return 6 * 1024 * 1024 * 1024  // 6GB
        #elseif os(iOS) || os(tvOS)
            return 1 * 1024 * 1024 * 1024  // 1GB
        #elseif os(watchOS)
            return 100 * 1024 * 1024       // 100MB
        #else
            return 1 * 1024 * 1024 * 1024  // 1GB default
        #endif
        }()
    }
}

/// The multipart download type options. This is a config option in `S3TransferManagerConfig`.
public enum MultipartDownloadType {
    /// Configures `S3TransferManager` to download an object from S3 using byte ranges.
    case range // Range HTTP header w/ getObject calls.
    /// Configures `S3TransferManager` to download an object from S3 using part numbers.
    case part // partNumber HTTP query parameter w/ getObject calls.
}

/// The interceptor provider that provides intercpetor for requests sent by `S3TransferManager`. For internal use only.
public class _S3TransferManagerInterceptorProvider: HttpInterceptorProvider { // swiftlint:disable:this type_name
    public func create<InputType, OutputType>() -> any Interceptor<InputType, OutputType, HTTPRequest, HTTPResponse> {
        return _S3TransferManagerInterceptor()
    }
}

/// The interceptor used to customize requests sent by `S3TransferManager`. For internal use only.
public class _S3TransferManagerInterceptor<InputType, OutputType>: Interceptor { // swiftlint:disable:this type_name
    public typealias RequestType = HTTPRequest
    public typealias ResponseType = HTTPResponse

    // Set business metrics feature ID for S3 Transfer Manager before serialization.
    public func modifyBeforeSerialization(context: some MutableInput<InputType>) async throws {
        context.getAttributes().businessMetrics = ["S3_TRANSFER": "G"]
    }
}
