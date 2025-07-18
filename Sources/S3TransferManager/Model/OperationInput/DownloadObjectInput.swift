//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import class Foundation.OutputStream
import struct Foundation.UUID
import struct Foundation.Date

/// The synthetic input type for the `downloadObject` operation of `S3TransferManager`.
public struct DownloadObjectInput: @unchecked Sendable, Identifiable {
    /*
        The type is `@unchecked Sendable` because of the `outputStream: OutputStream`, which isn't thread-safe by default. However, the way `.downloadObject` is implemented makes it concurency-safe. While `.downloadObject` transfer operation _does_ concurrently get an S3 object in parts, only one thread writes to `outputStream` at any given time because writes happen with the entire batch after each batch completes their concurrent download.
     */
    /// The unique ID for the operation; can be used to log or identify a specific request.
    public let id: String
    /// The destination stream the downloaded object will be written to.
    public let outputStream: OutputStream
    /// The list of transfer listeners whose callbacks will be called by `S3TransferManager` to report on transfer status and progress.
    public let transferListeners: [DownloadObjectTransferListener]

    /*
     Relevant fields from `GetObjectInput`.
     partNumber and range are excluded intentionally; S3TM does full object uploads / downloads only.
    */

    /// The bucket name containing the object. Directory buckets - When you use this operation with a directory bucket, you must use virtual-hosted-style requests in the format  Bucket-name.s3express-zone-id.region-code.amazonaws.com. Path-style requests are not supported. Directory bucket names must be unique in the chosen Zone (Availability Zone or Local Zone). Bucket names must follow the format  bucket-base-name--zone-id--x-s3 (for example,  amzn-s3-demo-bucket--usw2-az1--x-s3). For information about bucket naming restrictions, see [Directory bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/directory-bucket-naming-rules.html) in the Amazon S3 User Guide. Access points - When you use this action with an access point for general purpose buckets, you must provide the alias of the access point in place of the bucket name or specify the access point ARN. When you use this action with an access point for directory buckets, you must provide the access point name in place of the bucket name. When using the access point ARN, you must direct requests to the access point hostname. The access point hostname takes the form AccessPointName-AccountId.s3-accesspoint.Region.amazonaws.com. When using this action with an access point through the Amazon Web Services SDKs, you provide the access point ARN in place of the bucket name. For more information about access point ARNs, see [Using access points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-access-points.html) in the Amazon S3 User Guide. Object Lambda access points - When you use this action with an Object Lambda access point, you must direct requests to the Object Lambda access point hostname. The Object Lambda access point hostname takes the form AccessPointName-AccountId.s3-object-lambda.Region.amazonaws.com. Object Lambda access points are not supported by directory buckets. S3 on Outposts - When you use this action with S3 on Outposts, you must direct requests to the S3 on Outposts hostname. The S3 on Outposts hostname takes the form  AccessPointName-AccountId.outpostID.s3-outposts.Region.amazonaws.com. When you use this action with S3 on Outposts, the destination bucket must be the Outposts access point ARN or the access point alias. For more information about S3 on Outposts, see [What is S3 on Outposts?](https://docs.aws.amazon.com/AmazonS3/latest/userguide/S3onOutposts.html) in the Amazon S3 User Guide.
    /// This member is required.
    public var bucket: Swift.String
    /// To retrieve the checksum, this mode must be enabled.
    public var checksumMode: S3ClientTypes.ChecksumMode?
    /// The account ID of the expected bucket owner. If the account ID that you provide does not match the actual owner of the bucket, the request fails with the HTTP status code 403 Forbidden (access denied).
    public var expectedBucketOwner: Swift.String?
    /// Return the object only if its entity tag (ETag) is the same as the one specified in this header; otherwise, return a 412 Precondition Failed error. If both of the If-Match and If-Unmodified-Since headers are present in the request as follows: If-Match condition evaluates to true, and; If-Unmodified-Since condition evaluates to false; then, S3 returns 200 OK and the data requested. For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232).
    public var ifMatch: Swift.String?
    /// Return the object only if it has been modified since the specified time; otherwise, return a 304 Not Modified error. If both of the If-None-Match and If-Modified-Since headers are present in the request as follows: If-None-Match condition evaluates to false, and; If-Modified-Since condition evaluates to true; then, S3 returns 304 Not Modified status code. For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232).
    public var ifModifiedSince: Foundation.Date?
    /// Return the object only if its entity tag (ETag) is different from the one specified in this header; otherwise, return a 304 Not Modified error. If both of the If-None-Match and If-Modified-Since headers are present in the request as follows: If-None-Match condition evaluates to false, and; If-Modified-Since condition evaluates to true; then, S3 returns 304 Not Modified HTTP status code. For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232).
    public var ifNoneMatch: Swift.String?
    /// Return the object only if it has not been modified since the specified time; otherwise, return a 412 Precondition Failed error. If both of the If-Match and If-Unmodified-Since headers are present in the request as follows: If-Match condition evaluates to true, and; If-Unmodified-Since condition evaluates to false; then, S3 returns 200 OK and the data requested. For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232).
    public var ifUnmodifiedSince: Foundation.Date?
    /// Key of the object to get.
    /// This member is required.
    public var key: Swift.String
    /// Confirms that the requester knows that they will be charged for the request. Bucket owners need not specify this parameter in their requests. If either the source or destination S3 bucket has Requester Pays enabled, the requester will pay for corresponding charges to copy the object. For information about downloading objects from Requester Pays buckets, see [Downloading Objects in Requester Pays Buckets](https://docs.aws.amazon.com/AmazonS3/latest/dev/ObjectsinRequesterPaysBuckets.html) in the Amazon S3 User Guide. This functionality is not supported for directory buckets.
    public var requestPayer: S3ClientTypes.RequestPayer?
    /// Sets the Cache-Control header of the response.
    public var responseCacheControl: Swift.String?
    /// Sets the Content-Disposition header of the response.
    public var responseContentDisposition: Swift.String?
    /// Sets the Content-Encoding header of the response.
    public var responseContentEncoding: Swift.String?
    /// Sets the Content-Language header of the response.
    public var responseContentLanguage: Swift.String?
    /// Sets the Content-Type header of the response.
    public var responseContentType: Swift.String?
    /// Sets the Expires header of the response.
    public var responseExpires: Foundation.Date?
    /// Specifies the algorithm to use when decrypting the object (for example, AES256). If you encrypt an object by using server-side encryption with customer-provided encryption keys (SSE-C) when you store the object in Amazon S3, then when you GET the object, you must use the following headers:
    ///
    /// * x-amz-server-side-encryption-customer-algorithm
    ///
    /// * x-amz-server-side-encryption-customer-key
    ///
    /// * x-amz-server-side-encryption-customer-key-MD5
    ///
    ///
    /// For more information about SSE-C, see [Server-Side Encryption (Using Customer-Provided Encryption Keys)](https://docs.aws.amazon.com/AmazonS3/latest/dev/ServerSideEncryptionCustomerKeys.html) in the Amazon S3 User Guide. This functionality is not supported for directory buckets.
    public var sseCustomerAlgorithm: Swift.String?
    /// Specifies the customer-provided encryption key that you originally provided for Amazon S3 to encrypt the data before storing it. This value is used to decrypt the object when recovering it and must match the one used when storing the data. The key must be appropriate for use with the algorithm specified in the x-amz-server-side-encryption-customer-algorithm header. If you encrypt an object by using server-side encryption with customer-provided encryption keys (SSE-C) when you store the object in Amazon S3, then when you GET the object, you must use the following headers:
    ///
    /// * x-amz-server-side-encryption-customer-algorithm
    ///
    /// * x-amz-server-side-encryption-customer-key
    ///
    /// * x-amz-server-side-encryption-customer-key-MD5
    ///
    ///
    /// For more information about SSE-C, see [Server-Side Encryption (Using Customer-Provided Encryption Keys)](https://docs.aws.amazon.com/AmazonS3/latest/dev/ServerSideEncryptionCustomerKeys.html) in the Amazon S3 User Guide. This functionality is not supported for directory buckets.
    public var sseCustomerKey: Swift.String?
    /// Specifies the 128-bit MD5 digest of the customer-provided encryption key according to RFC 1321. Amazon S3 uses this header for a message integrity check to ensure that the encryption key was transmitted without error. If you encrypt an object by using server-side encryption with customer-provided encryption keys (SSE-C) when you store the object in Amazon S3, then when you GET the object, you must use the following headers:
    ///
    /// * x-amz-server-side-encryption-customer-algorithm
    ///
    /// * x-amz-server-side-encryption-customer-key
    ///
    /// * x-amz-server-side-encryption-customer-key-MD5
    ///
    ///
    /// For more information about SSE-C, see [Server-Side Encryption (Using Customer-Provided Encryption Keys)](https://docs.aws.amazon.com/AmazonS3/latest/dev/ServerSideEncryptionCustomerKeys.html) in the Amazon S3 User Guide. This functionality is not supported for directory buckets.
    public var sseCustomerKeyMD5: Swift.String?
    /// Version ID used to reference a specific version of the object. By default, the GetObject operation returns the current version of an object. To return a different version, use the versionId subresource.
    ///
    /// * If you include a versionId in your request header, you must have the s3:GetObjectVersion permission to access a specific version of an object. The s3:GetObject permission is not required in this scenario.
    ///
    /// * If you request the current version of an object without a specific versionId in the request header, only the s3:GetObject permission is required. The s3:GetObjectVersion permission is not required in this scenario.
    ///
    /// * Directory buckets - S3 Versioning isn't enabled and supported for directory buckets. For this API operation, only the null value of the version ID is supported by directory buckets. You can only specify null to the versionId query parameter in the request.
    ///
    ///
    /// For more information about versioning, see [PutBucketVersioning](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutBucketVersioning.html).
    public var versionId: Swift.String?

    /// Initializes `DownloadObjectInput` with provided parameters.
    public init(
        outputStream: OutputStream,
        bucket: Swift.String,
        checksumMode: S3ClientTypes.ChecksumMode? = nil,
        expectedBucketOwner: Swift.String? = nil,
        ifMatch: Swift.String? = nil,
        ifModifiedSince: Foundation.Date? = nil,
        ifNoneMatch: Swift.String? = nil,
        ifUnmodifiedSince: Foundation.Date? = nil,
        key: Swift.String,
        requestPayer: S3ClientTypes.RequestPayer? = nil,
        responseCacheControl: Swift.String? = nil,
        responseContentDisposition: Swift.String? = nil,
        responseContentEncoding: Swift.String? = nil,
        responseContentLanguage: Swift.String? = nil,
        responseContentType: Swift.String? = nil,
        responseExpires: Foundation.Date? = nil,
        sseCustomerAlgorithm: Swift.String? = nil,
        sseCustomerKey: Swift.String? = nil,
        sseCustomerKeyMD5: Swift.String? = nil,
        versionId: Swift.String? = nil,
        transferListeners: [DownloadObjectTransferListener] = []
    ) {
        self.id = UUID().uuidString
        self.outputStream = outputStream
        self.bucket = bucket
        self.checksumMode = checksumMode
        self.expectedBucketOwner = expectedBucketOwner
        self.ifMatch = ifMatch
        self.ifModifiedSince = ifModifiedSince
        self.ifNoneMatch = ifNoneMatch
        self.ifUnmodifiedSince = ifUnmodifiedSince
        self.key = key
        self.requestPayer = requestPayer
        self.responseCacheControl = responseCacheControl
        self.responseContentDisposition = responseContentDisposition
        self.responseContentEncoding = responseContentEncoding
        self.responseContentLanguage = responseContentLanguage
        self.responseContentType = responseContentType
        self.responseExpires = responseExpires
        self.sseCustomerAlgorithm = sseCustomerAlgorithm
        self.sseCustomerKey = sseCustomerKey
        self.sseCustomerKeyMD5 = sseCustomerKeyMD5
        self.versionId = versionId
        self.transferListeners = transferListeners
    }

    // Internal initializer used by the `downloadBucket` operation to provide specific operation IDs for
    //  "child" requests. Allows grouping requests together by the operation IDs.
    internal init(
        id: String,
        outputStream: OutputStream,
        bucket: Swift.String,
        checksumMode: S3ClientTypes.ChecksumMode? = nil,
        key: Swift.String,
        transferListeners: [DownloadObjectTransferListener] = []
    ) {
        self.id = id
        self.outputStream = outputStream
        self.bucket = bucket
        self.checksumMode = checksumMode
        self.key = key
        self.transferListeners = transferListeners
    }

    // MARK: - Internal helper functions for converting / transforming input(s).

    func deriveGetObjectInput(
        withPartNumber: Int? = nil,
        withRange: String? = nil
    ) -> GetObjectInput {
        return GetObjectInput(
            bucket: self.bucket,
            checksumMode: self.checksumMode,
            expectedBucketOwner: self.expectedBucketOwner,
            ifMatch: self.ifMatch,
            ifModifiedSince: self.ifModifiedSince,
            ifNoneMatch: self.ifNoneMatch,
            ifUnmodifiedSince: self.ifUnmodifiedSince,
            key: self.key,
            partNumber: withPartNumber,
            range: withRange,
            requestPayer: self.requestPayer,
            responseCacheControl: self.responseCacheControl,
            responseContentDisposition: self.responseContentDisposition,
            responseContentEncoding: self.responseContentEncoding,
            responseContentLanguage: self.responseContentLanguage,
            responseContentType: self.responseContentType,
            responseExpires: self.responseExpires,
            sseCustomerAlgorithm: self.sseCustomerAlgorithm,
            sseCustomerKey: self.sseCustomerKey,
            sseCustomerKeyMD5: self.sseCustomerKeyMD5,
            versionId: self.versionId
        )
    }
}
