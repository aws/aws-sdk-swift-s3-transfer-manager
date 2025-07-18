//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import AWSS3
import enum Smithy.ByteStream
import struct Foundation.UUID
import struct Foundation.Date

/// The synthetic input type for the `uploadObject` operation of `S3TransferManager`.
public struct UploadObjectInput: Sendable, Identifiable {
    /// The unique ID for the operation; can be used to log or identify a specific request.
    public let id: String
    /// The list of transfer listeners whose callbacks will be called by `S3TransferManager` to report on transfer status and progress.
    public let transferListeners: [UploadObjectTransferListener]

    /*
     Relevant fields from `PutObjectInput`.
    */

    /// The canned ACL to apply to the object. For more information, see [Canned ACL](https://docs.aws.amazon.com/AmazonS3/latest/dev/acl-overview.html#CannedACL) in the Amazon S3 User Guide. When adding a new object, you can use headers to grant ACL-based permissions to individual Amazon Web Services accounts or to predefined groups defined by Amazon S3. These permissions are then added to the ACL on the object. By default, all objects are private. Only the owner has full access control. For more information, see [Access Control List (ACL) Overview](https://docs.aws.amazon.com/AmazonS3/latest/dev/acl-overview.html) and [Managing ACLs Using the REST API](https://docs.aws.amazon.com/AmazonS3/latest/dev/acl-using-rest-api.html) in the Amazon S3 User Guide. If the bucket that you're uploading objects to uses the bucket owner enforced setting for S3 Object Ownership, ACLs are disabled and no longer affect permissions. Buckets that use this setting only accept PUT requests that don't specify an ACL or PUT requests that specify bucket owner full control ACLs, such as the bucket-owner-full-control canned ACL or an equivalent form of this ACL expressed in the XML format. PUT requests that contain other ACLs (for example, custom grants to certain Amazon Web Services accounts) fail and return a 400 error with the error code AccessControlListNotSupported. For more information, see [ Controlling ownership of objects and disabling ACLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html) in the Amazon S3 User Guide.
    ///
    /// * This functionality is not supported for directory buckets.
    ///
    /// * This functionality is not supported for Amazon S3 on Outposts.
    public var acl: S3ClientTypes.ObjectCannedACL?
    /// Object data.
    public var body: Smithy.ByteStream
    /// The bucket name to which the PUT action was initiated. Directory buckets - When you use this operation with a directory bucket, you must use virtual-hosted-style requests in the format  Bucket-name.s3express-zone-id.region-code.amazonaws.com. Path-style requests are not supported. Directory bucket names must be unique in the chosen Zone (Availability Zone or Local Zone). Bucket names must follow the format  bucket-base-name--zone-id--x-s3 (for example,  amzn-s3-demo-bucket--usw2-az1--x-s3). For information about bucket naming restrictions, see [Directory bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/directory-bucket-naming-rules.html) in the Amazon S3 User Guide. Access points - When you use this action with an access point for general purpose buckets, you must provide the alias of the access point in place of the bucket name or specify the access point ARN. When you use this action with an access point for directory buckets, you must provide the access point name in place of the bucket name. When using the access point ARN, you must direct requests to the access point hostname. The access point hostname takes the form AccessPointName-AccountId.s3-accesspoint.Region.amazonaws.com. When using this action with an access point through the Amazon Web Services SDKs, you provide the access point ARN in place of the bucket name. For more information about access point ARNs, see [Using access points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-access-points.html) in the Amazon S3 User Guide. Object Lambda access points are not supported by directory buckets. S3 on Outposts - When you use this action with S3 on Outposts, you must direct requests to the S3 on Outposts hostname. The S3 on Outposts hostname takes the form  AccessPointName-AccountId.outpostID.s3-outposts.Region.amazonaws.com. When you use this action with S3 on Outposts, the destination bucket must be the Outposts access point ARN or the access point alias. For more information about S3 on Outposts, see [What is S3 on Outposts?](https://docs.aws.amazon.com/AmazonS3/latest/userguide/S3onOutposts.html) in the Amazon S3 User Guide.
    /// This member is required.
    public var bucket: Swift.String
    /// Specifies whether Amazon S3 should use an S3 Bucket Key for object encryption with server-side encryption using Key Management Service (KMS) keys (SSE-KMS). General purpose buckets - Setting this header to true causes Amazon S3 to use an S3 Bucket Key for object encryption with SSE-KMS. Also, specifying this header with a PUT action doesn't affect bucket-level settings for S3 Bucket Key. Directory buckets - S3 Bucket Keys are always enabled for GET and PUT operations in a directory bucket and can’t be disabled. S3 Bucket Keys aren't supported, when you copy SSE-KMS encrypted objects from general purpose buckets to directory buckets, from directory buckets to general purpose buckets, or between directory buckets, through [CopyObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html), [UploadPartCopy](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPartCopy.html), [the Copy operation in Batch Operations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/directory-buckets-objects-Batch-Ops), or [the import jobs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/create-import-job). In this case, Amazon S3 makes a call to KMS every time a copy request is made for a KMS-encrypted object.
    public var bucketKeyEnabled: Swift.Bool?
    /// Can be used to specify caching behavior along the request/reply chain. For more information, see [http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.9](http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.9).
    public var cacheControl: Swift.String?
    /// Indicates the algorithm used to create the checksum for the object when you use the SDK. This header will not provide any additional functionality if you don't use the SDK. When you send this header, there must be a corresponding x-amz-checksum-algorithm  or x-amz-trailer header sent. Otherwise, Amazon S3 fails the request with the HTTP status code 400 Bad Request. For the x-amz-checksum-algorithm  header, replace  algorithm  with the supported algorithm from the following list:
    ///
    /// * CRC32
    ///
    /// * CRC32C
    ///
    /// * CRC64NVME
    ///
    /// * SHA1
    ///
    /// * SHA256
    ///
    ///
    /// For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the Amazon S3 User Guide. If the individual checksum value you provide through x-amz-checksum-algorithm  doesn't match the checksum algorithm you set through x-amz-sdk-checksum-algorithm, Amazon S3 fails the request with a BadDigest error. The Content-MD5 or x-amz-sdk-checksum-algorithm header is required for any request to upload an object with a retention period configured using Amazon S3 Object Lock. For more information, see [Uploading objects to an Object Lock enabled bucket ](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-managing.html#object-lock-put-object) in the Amazon S3 User Guide. For directory buckets, when you use Amazon Web Services SDKs, CRC32 is the default checksum algorithm that's used for performance.
    public var checksumAlgorithm: S3ClientTypes.ChecksumAlgorithm?
    /// This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 32-bit CRC32 checksum of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the Amazon S3 User Guide.
    public var checksumCRC32: Swift.String?
    /// This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 32-bit CRC32C checksum of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the Amazon S3 User Guide.
    public var checksumCRC32C: Swift.String?
    /// This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 64-bit CRC64NVME checksum of the object. The CRC64NVME checksum is always a full object checksum. For more information, see [Checking object integrity in the Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html).
    public var checksumCRC64NVME: Swift.String?
    /// This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 160-bit SHA1 digest of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the Amazon S3 User Guide.
    public var checksumSHA1: Swift.String?
    /// This header can be used as a data integrity check to verify that the data received is the same data that was originally sent. This header specifies the Base64 encoded, 256-bit SHA256 digest of the object. For more information, see [Checking object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html) in the Amazon S3 User Guide.
    public var checksumSHA256: Swift.String?
    /// Specifies presentational information for the object. For more information, see [https://www.rfc-editor.org/rfc/rfc6266#section-4](https://www.rfc-editor.org/rfc/rfc6266#section-4).
    public var contentDisposition: Swift.String?
    /// Specifies what content encodings have been applied to the object and thus what decoding mechanisms must be applied to obtain the media-type referenced by the Content-Type header field. For more information, see [https://www.rfc-editor.org/rfc/rfc9110.html#field.content-encoding](https://www.rfc-editor.org/rfc/rfc9110.html#field.content-encoding).
    public var contentEncoding: Swift.String?
    /// The language the content is in.
    public var contentLanguage: Swift.String?
    /// A standard MIME type describing the format of the contents. For more information, see [https://www.rfc-editor.org/rfc/rfc9110.html#name-content-type](https://www.rfc-editor.org/rfc/rfc9110.html#name-content-type).
    public var contentType: Swift.String?
    /// The account ID of the expected bucket owner. If the account ID that you provide does not match the actual owner of the bucket, the request fails with the HTTP status code 403 Forbidden (access denied).
    public var expectedBucketOwner: Swift.String?
    /// The date and time at which the object is no longer cacheable. For more information, see [https://www.rfc-editor.org/rfc/rfc7234#section-5.3](https://www.rfc-editor.org/rfc/rfc7234#section-5.3).
    public var expires: Swift.String?
    /// Gives the grantee READ, READ_ACP, and WRITE_ACP permissions on the object.
    ///
    /// * This functionality is not supported for directory buckets.
    ///
    /// * This functionality is not supported for Amazon S3 on Outposts.
    public var grantFullControl: Swift.String?
    /// Allows grantee to read the object data and its metadata.
    ///
    /// * This functionality is not supported for directory buckets.
    ///
    /// * This functionality is not supported for Amazon S3 on Outposts.
    public var grantRead: Swift.String?
    /// Allows grantee to read the object ACL.
    ///
    /// * This functionality is not supported for directory buckets.
    ///
    /// * This functionality is not supported for Amazon S3 on Outposts.
    public var grantReadACP: Swift.String?
    /// Allows grantee to write the ACL for the applicable object.
    ///
    /// * This functionality is not supported for directory buckets.
    ///
    /// * This functionality is not supported for Amazon S3 on Outposts.
    public var grantWriteACP: Swift.String?
    /// Uploads the object only if the ETag (entity tag) value provided during the WRITE operation matches the ETag of the object in S3. If the ETag values do not match, the operation returns a 412 Precondition Failed error. If a conflicting operation occurs during the upload S3 returns a 409 ConditionalRequestConflict response. On a 409 failure you should fetch the object's ETag and retry the upload. Expects the ETag value as a string. For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232), or [Conditional requests](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-requests.html) in the Amazon S3 User Guide.
    public var ifMatch: Swift.String?
    /// Uploads the object only if the object key name does not already exist in the bucket specified. Otherwise, Amazon S3 returns a 412 Precondition Failed error. If a conflicting operation occurs during the upload S3 returns a 409 ConditionalRequestConflict response. On a 409 failure you should retry the upload. Expects the '*' (asterisk) character. For more information about conditional requests, see [RFC 7232](https://tools.ietf.org/html/rfc7232), or [Conditional requests](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-requests.html) in the Amazon S3 User Guide.
    public var ifNoneMatch: Swift.String?
    /// Object key for which the PUT action was initiated.
    /// This member is required.
    public var key: Swift.String
    /// A map of metadata to store with the object in S3.
    public var metadata: [Swift.String: Swift.String]?
    /// Specifies whether a legal hold will be applied to this object. For more information about S3 Object Lock, see [Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/dev/object-lock.html) in the Amazon S3 User Guide. This functionality is not supported for directory buckets.
    public var objectLockLegalHoldStatus: S3ClientTypes.ObjectLockLegalHoldStatus?
    /// The Object Lock mode that you want to apply to this object. This functionality is not supported for directory buckets.
    public var objectLockMode: S3ClientTypes.ObjectLockMode?
    /// The date and time when you want this object's Object Lock to expire. Must be formatted as a timestamp parameter. This functionality is not supported for directory buckets.
    public var objectLockRetainUntilDate: Foundation.Date?
    /// Confirms that the requester knows that they will be charged for the request. Bucket owners need not specify this parameter in their requests. If either the source or destination S3 bucket has Requester Pays enabled, the requester will pay for corresponding charges to copy the object. For information about downloading objects from Requester Pays buckets, see [Downloading Objects in Requester Pays Buckets](https://docs.aws.amazon.com/AmazonS3/latest/dev/ObjectsinRequesterPaysBuckets.html) in the Amazon S3 User Guide. This functionality is not supported for directory buckets.
    public var requestPayer: S3ClientTypes.RequestPayer?
    /// The server-side encryption algorithm that was used when you store this object in Amazon S3 or Amazon FSx.
    ///
    /// * General purpose buckets - You have four mutually exclusive options to protect data using server-side encryption in Amazon S3, depending on how you choose to manage the encryption keys. Specifically, the encryption key options are Amazon S3 managed keys (SSE-S3), Amazon Web Services KMS keys (SSE-KMS or DSSE-KMS), and customer-provided keys (SSE-C). Amazon S3 encrypts data with server-side encryption by using Amazon S3 managed keys (SSE-S3) by default. You can optionally tell Amazon S3 to encrypt data at rest by using server-side encryption with other key options. For more information, see [Using Server-Side Encryption](https://docs.aws.amazon.com/AmazonS3/latest/dev/UsingServerSideEncryption.html) in the Amazon S3 User Guide.
    ///
    /// * Directory buckets - For directory buckets, there are only two supported options for server-side encryption: server-side encryption with Amazon S3 managed keys (SSE-S3) (AES256) and server-side encryption with KMS keys (SSE-KMS) (aws:kms). We recommend that the bucket's default encryption uses the desired encryption configuration and you don't override the bucket default encryption in your CreateSession requests or PUT object requests. Then, new objects are automatically encrypted with the desired encryption settings. For more information, see [Protecting data with server-side encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-serv-side-encryption.html) in the Amazon S3 User Guide. For more information about the encryption overriding behaviors in directory buckets, see [Specifying server-side encryption with KMS for new object uploads](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-specifying-kms-encryption.html). In the Zonal endpoint API calls (except [CopyObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html) and [UploadPartCopy](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPartCopy.html)) using the REST API, the encryption request headers must match the encryption settings that are specified in the CreateSession request. You can't override the values of the encryption settings (x-amz-server-side-encryption, x-amz-server-side-encryption-aws-kms-key-id, x-amz-server-side-encryption-context, and x-amz-server-side-encryption-bucket-key-enabled) that are specified in the CreateSession request. You don't need to explicitly specify these encryption settings values in Zonal endpoint API calls, and Amazon S3 will use the encryption settings values from the CreateSession request to protect new objects in the directory bucket. When you use the CLI or the Amazon Web Services SDKs, for CreateSession, the session token refreshes automatically to avoid service interruptions when a session expires. The CLI or the Amazon Web Services SDKs use the bucket's default encryption configuration for the CreateSession request. It's not supported to override the encryption settings values in the CreateSession request. So in the Zonal endpoint API calls (except [CopyObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html) and [UploadPartCopy](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPartCopy.html)), the encryption request headers must match the default encryption configuration of the directory bucket.
    ///
    /// * S3 access points for Amazon FSx - When accessing data stored in Amazon FSx file systems using S3 access points, the only valid server side encryption option is aws:fsx. All Amazon FSx file systems have encryption configured by default and are encrypted at rest. Data is automatically encrypted before being written to the file system, and automatically decrypted as it is read. These processes are handled transparently by Amazon FSx.
    public var serverSideEncryption: S3ClientTypes.ServerSideEncryption?
    /// Specifies the algorithm to use when encrypting the object (for example, AES256). This functionality is not supported for directory buckets.
    public var sseCustomerAlgorithm: Swift.String?
    /// Specifies the customer-provided encryption key for Amazon S3 to use in encrypting data. This value is used to store the object and then it is discarded; Amazon S3 does not store the encryption key. The key must be appropriate for use with the algorithm specified in the x-amz-server-side-encryption-customer-algorithm header. This functionality is not supported for directory buckets.
    public var sseCustomerKey: Swift.String?
    /// Specifies the 128-bit MD5 digest of the encryption key according to RFC 1321. Amazon S3 uses this header for a message integrity check to ensure that the encryption key was transmitted without error. This functionality is not supported for directory buckets.
    public var sseCustomerKeyMD5: Swift.String?
    /// Specifies the Amazon Web Services KMS Encryption Context as an additional encryption context to use for object encryption. The value of this header is a Base64 encoded string of a UTF-8 encoded JSON, which contains the encryption context as key-value pairs. This value is stored as object metadata and automatically gets passed on to Amazon Web Services KMS for future GetObject operations on this object. General purpose buckets - This value must be explicitly added during CopyObject operations if you want an additional encryption context for your object. For more information, see [Encryption context](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html#encryption-context) in the Amazon S3 User Guide. Directory buckets - You can optionally provide an explicit encryption context value. The value must match the default encryption context - the bucket Amazon Resource Name (ARN). An additional encryption context value is not supported.
    public var ssekmsEncryptionContext: Swift.String?
    /// Specifies the KMS key ID (Key ID, Key ARN, or Key Alias) to use for object encryption. If the KMS key doesn't exist in the same account that's issuing the command, you must use the full Key ARN not the Key ID. General purpose buckets - If you specify x-amz-server-side-encryption with aws:kms or aws:kms:dsse, this header specifies the ID (Key ID, Key ARN, or Key Alias) of the KMS key to use. If you specify x-amz-server-side-encryption:aws:kms or x-amz-server-side-encryption:aws:kms:dsse, but do not provide x-amz-server-side-encryption-aws-kms-key-id, Amazon S3 uses the Amazon Web Services managed key (aws/s3) to protect the data. Directory buckets - To encrypt data using SSE-KMS, it's recommended to specify the x-amz-server-side-encryption header to aws:kms. Then, the x-amz-server-side-encryption-aws-kms-key-id header implicitly uses the bucket's default KMS customer managed key ID. If you want to explicitly set the  x-amz-server-side-encryption-aws-kms-key-id header, it must match the bucket's default customer managed key (using key ID or ARN, not alias). Your SSE-KMS configuration can only support 1 [customer managed key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#customer-cmk) per directory bucket's lifetime. The [Amazon Web Services managed key](https://docs.aws.amazon.com/kms/latest/developerguide/concepts.html#aws-managed-cmk) (aws/s3) isn't supported. Incorrect key specification results in an HTTP 400 Bad Request error.
    public var ssekmsKeyId: Swift.String?
    /// By default, Amazon S3 uses the STANDARD Storage Class to store newly created objects. The STANDARD storage class provides high durability and high availability. Depending on performance needs, you can specify a different Storage Class. For more information, see [Storage Classes](https://docs.aws.amazon.com/AmazonS3/latest/dev/storage-class-intro.html) in the Amazon S3 User Guide.
    ///
    /// * Directory buckets only support EXPRESS_ONEZONE (the S3 Express One Zone storage class) in Availability Zones and ONEZONE_IA (the S3 One Zone-Infrequent Access storage class) in Dedicated Local Zones.
    ///
    /// * Amazon S3 on Outposts only uses the OUTPOSTS Storage Class.
    public var storageClass: S3ClientTypes.StorageClass?
    /// The tag-set for the object. The tag-set must be encoded as URL Query parameters. (For example, "Key1=Value1") This functionality is not supported for directory buckets.
    public var tagging: Swift.String?
    /// If the bucket is configured as a website, redirects requests for this object to another object in the same bucket or to an external URL. Amazon S3 stores the value of this header in the object metadata. For information about object metadata, see [Object Key and Metadata](https://docs.aws.amazon.com/AmazonS3/latest/dev/UsingMetadata.html) in the Amazon S3 User Guide. In the following example, the request header sets the redirect to an object (anotherPage.html) in the same bucket: x-amz-website-redirect-location: /anotherPage.html In the following example, the request header sets the object redirect to another website: x-amz-website-redirect-location: http://www.example.com/ For more information about website hosting in Amazon S3, see [Hosting Websites on Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/dev/WebsiteHosting.html) and [How to Configure Website Page Redirects](https://docs.aws.amazon.com/AmazonS3/latest/dev/how-to-page-redirect.html) in the Amazon S3 User Guide. This functionality is not supported for directory buckets.
    public var websiteRedirectLocation: Swift.String?

    /// Initializes `UploadObjectInput` with provided parameters.
    public init(
        acl: S3ClientTypes.ObjectCannedACL? = nil,
        body: Smithy.ByteStream,
        bucket: Swift.String,
        bucketKeyEnabled: Swift.Bool? = nil,
        cacheControl: Swift.String? = nil,
        checksumAlgorithm: S3ClientTypes.ChecksumAlgorithm? = nil,
        checksumCRC32: Swift.String? = nil,
        checksumCRC32C: Swift.String? = nil,
        checksumCRC64NVME: Swift.String? = nil,
        checksumSHA1: Swift.String? = nil,
        checksumSHA256: Swift.String? = nil,
        contentDisposition: Swift.String? = nil,
        contentEncoding: Swift.String? = nil,
        contentLanguage: Swift.String? = nil,
        contentType: Swift.String? = nil,
        expectedBucketOwner: Swift.String? = nil,
        expires: Swift.String? = nil,
        grantFullControl: Swift.String? = nil,
        grantRead: Swift.String? = nil,
        grantReadACP: Swift.String? = nil,
        grantWriteACP: Swift.String? = nil,
        ifMatch: Swift.String? = nil,
        ifNoneMatch: Swift.String? = nil,
        key: Swift.String,
        metadata: [Swift.String: Swift.String]? = nil,
        objectLockLegalHoldStatus: S3ClientTypes.ObjectLockLegalHoldStatus? = nil,
        objectLockMode: S3ClientTypes.ObjectLockMode? = nil,
        objectLockRetainUntilDate: Foundation.Date? = nil,
        requestPayer: S3ClientTypes.RequestPayer? = nil,
        serverSideEncryption: S3ClientTypes.ServerSideEncryption? = nil,
        sseCustomerAlgorithm: Swift.String? = nil,
        sseCustomerKey: Swift.String? = nil,
        sseCustomerKeyMD5: Swift.String? = nil,
        ssekmsEncryptionContext: Swift.String? = nil,
        ssekmsKeyId: Swift.String? = nil,
        storageClass: S3ClientTypes.StorageClass? = nil,
        tagging: Swift.String? = nil,
        websiteRedirectLocation: Swift.String? = nil,
        transferListeners: [UploadObjectTransferListener] = []
    ) {
        self.id = UUID().uuidString
        self.acl = acl
        self.body = body
        self.bucket = bucket
        self.bucketKeyEnabled = bucketKeyEnabled
        self.cacheControl = cacheControl
        self.checksumAlgorithm = checksumAlgorithm
        self.checksumCRC32 = checksumCRC32
        self.checksumCRC32C = checksumCRC32C
        self.checksumCRC64NVME = checksumCRC64NVME
        self.checksumSHA1 = checksumSHA1
        self.checksumSHA256 = checksumSHA256
        self.contentDisposition = contentDisposition
        self.contentEncoding = contentEncoding
        self.contentLanguage = contentLanguage
        self.contentType = contentType
        self.expectedBucketOwner = expectedBucketOwner
        self.expires = expires
        self.grantFullControl = grantFullControl
        self.grantRead = grantRead
        self.grantReadACP = grantReadACP
        self.grantWriteACP = grantWriteACP
        self.ifMatch = ifMatch
        self.ifNoneMatch = ifNoneMatch
        self.key = key
        self.metadata = metadata
        self.objectLockLegalHoldStatus = objectLockLegalHoldStatus
        self.objectLockMode = objectLockMode
        self.objectLockRetainUntilDate = objectLockRetainUntilDate
        self.requestPayer = requestPayer
        self.serverSideEncryption = serverSideEncryption
        self.sseCustomerAlgorithm = sseCustomerAlgorithm
        self.sseCustomerKey = sseCustomerKey
        self.sseCustomerKeyMD5 = sseCustomerKeyMD5
        self.ssekmsEncryptionContext = ssekmsEncryptionContext
        self.ssekmsKeyId = ssekmsKeyId
        self.storageClass = storageClass
        self.tagging = tagging
        self.websiteRedirectLocation = websiteRedirectLocation
        self.transferListeners = transferListeners
    }

    // Internal initializer used by the `uploadDirectory` operation to provide specific operation IDs for
    //  "child" requests. Allows grouping requests together by the operation IDs.
    internal init(
        id: String,
        body: Smithy.ByteStream,
        bucket: Swift.String,
        checksumAlgorithm: S3ClientTypes.ChecksumAlgorithm? = nil,
        key: Swift.String,
        transferListeners: [UploadObjectTransferListener] = []
    ) {
        self.id = id
        self.body = body
        self.bucket = bucket
        self.checksumAlgorithm = checksumAlgorithm
        self.key = key
        self.transferListeners = transferListeners
    }

    // MARK: - Internal helper functions for conversion to specific operation input(s).

    func derivePutObjectInput() -> PutObjectInput {
        return PutObjectInput(
            body: self.body,
            bucket: self.bucket,
            checksumAlgorithm: self.checksumAlgorithm,
            checksumCRC32: self.checksumCRC32,
            checksumCRC32C: self.checksumCRC32C,
            checksumCRC64NVME: self.checksumCRC64NVME,
            checksumSHA1: self.checksumSHA1,
            checksumSHA256: self.checksumSHA256,
            expectedBucketOwner: self.expectedBucketOwner,
            key: self.key,
            requestPayer: self.requestPayer,
            sseCustomerAlgorithm: self.sseCustomerAlgorithm,
            sseCustomerKey: self.sseCustomerKey,
            sseCustomerKeyMD5: self.sseCustomerKeyMD5
        )
    }

    func deriveCreateMultipartUploadInput() -> CreateMultipartUploadInput {
        return CreateMultipartUploadInput(
            acl: self.acl,
            bucket: self.bucket,
            bucketKeyEnabled: self.bucketKeyEnabled,
            cacheControl: self.cacheControl,
            // Determine `checksumAlgorithm`.
            checksumAlgorithm: resolveChecksumAlgorithmForCreateMPUInput(),
            // Determine `checksumType`.
            checksumType: resolveChecksumType(),
            contentDisposition: self.contentDisposition,
            contentEncoding: self.contentEncoding,
            contentLanguage: self.contentLanguage,
            contentType: self.contentType,
            expectedBucketOwner: self.expectedBucketOwner,
            expires: self.expires,
            grantFullControl: self.grantFullControl,
            grantRead: self.grantRead,
            grantReadACP: self.grantReadACP,
            grantWriteACP: self.grantWriteACP,
            key: self.key,
            metadata: self.metadata,
            objectLockLegalHoldStatus: self.objectLockLegalHoldStatus,
            objectLockMode: self.objectLockMode,
            objectLockRetainUntilDate: self.objectLockRetainUntilDate,
            requestPayer: self.requestPayer,
            serverSideEncryption: self.serverSideEncryption,
            sseCustomerAlgorithm: self.sseCustomerAlgorithm,
            sseCustomerKey: self.sseCustomerKey,
            sseCustomerKeyMD5: self.sseCustomerKeyMD5,
            ssekmsEncryptionContext: self.ssekmsEncryptionContext,
            ssekmsKeyId: self.ssekmsKeyId,
            storageClass: self.storageClass,
            tagging: self.tagging,
            websiteRedirectLocation: self.websiteRedirectLocation
        )
    }

    func deriveUploadPartInput(
        body: Smithy.ByteStream,
        partNumber: Int,
        uploadID: String
    ) -> UploadPartInput {
        return UploadPartInput(
            body: body,
            bucket: self.bucket,
            // Determine checksum algorithm.
            checksumAlgorithm: resolveChecksumAlgorithmForCreateMPUInput(),
            expectedBucketOwner: self.expectedBucketOwner,
            key: self.key,
            partNumber: partNumber,
            requestPayer: self.requestPayer,
            sseCustomerAlgorithm: self.sseCustomerAlgorithm,
            sseCustomerKey: self.sseCustomerKey,
            sseCustomerKeyMD5: self.sseCustomerKeyMD5,
            uploadId: uploadID
        )
    }

    func deriveCompleteMultipartUploadInput(
        multipartUpload: S3ClientTypes.CompletedMultipartUpload,
        uploadID: String,
        mpuObjectSize: Int
    ) -> CompleteMultipartUploadInput {
        return CompleteMultipartUploadInput(
            bucket: self.bucket,
            checksumCRC32: self.checksumCRC32,
            checksumCRC32C: self.checksumCRC32C,
            checksumCRC64NVME: self.checksumCRC64NVME,
            checksumSHA1: self.checksumSHA1,
            checksumSHA256: self.checksumSHA256,
            // Determine `checksumType`.
            checksumType: resolveChecksumType(),
            expectedBucketOwner: self.expectedBucketOwner,
            ifMatch: self.ifMatch,
            ifNoneMatch: self.ifNoneMatch,
            key: self.key,
            mpuObjectSize: mpuObjectSize,
            multipartUpload: multipartUpload,
            requestPayer: self.requestPayer,
            sseCustomerAlgorithm: self.sseCustomerAlgorithm,
            sseCustomerKey: self.sseCustomerKey,
            sseCustomerKeyMD5: self.sseCustomerKeyMD5,
            uploadId: uploadID
        )
    }

    func deriveAbortMultipartUploadInput(
        uploadID: String
    ) -> AbortMultipartUploadInput {
        return AbortMultipartUploadInput(
            bucket: self.bucket,
            expectedBucketOwner: self.expectedBucketOwner,
            key: self.key,
            requestPayer: self.requestPayer,
            uploadId: uploadID
        )
    }

    // MARK: - Helper functions for checksum type & algorithm properties.

    private func resolveChecksumAlgorithmForCreateMPUInput() -> S3ClientTypes.ChecksumAlgorithm {
        // If algorithm was configured, just return that.
        if let algo = self.checksumAlgorithm {
            return algo
        }
        // Otherwise, check if any checksum value was provided; return matching algorithm if present.
        // Follow the algorithm priority in `smithy-swift/Sources/SmithyChecksums/ChecksumAlgorithm.swift`.
        if self.checksumCRC32C != nil {
            return .crc32c
        } else if self.checksumCRC32 != nil {
            return .crc32
        } else if self.checksumCRC64NVME != nil {
            return .crc64nvme
        } else if self.checksumSHA1 != nil {
            return .sha1
        } else if self.checksumSHA256 != nil {
            return .sha256
        }
        // If no checksum hash nor checksum algorithm was configured, return CRC32.
        // It's the default algorithm for Swift SDK.
        return .crc32
    }

    /*
        `CreateMultipartUploadInput` & `CompleteMultipartUploadInput` have the `checksumType` input member.
        `PutObjectInput` doesn't have that member.
        So, for create / complete MPU inputs, must determine the value of `checksumType` based on whether the full object checksum was manually provided by the user in `PutObjectInput` or not.
     */
    private func resolveChecksumType() -> S3ClientTypes.ChecksumType? {
        let providedChecksum = self.checksumCRC32
        ?? self.checksumCRC32C
        ?? self.checksumSHA1
        ?? self.checksumSHA256
        ?? self.checksumCRC64NVME
        if providedChecksum != nil {
            return .fullObject
        } else {
            return .composite
        }
    }
}
