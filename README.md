# Amazon S3 Transfer Manager for Swift

## ⚠️ Developer Preview

This library is currently in developer preview and is NOT recommended for production environments.

It is meant for early access and feedback gathering at this time. We'd love to hear from you on use cases, feature prioritization, and API feedback.

See the AWS SDK and Tools [maintenance policy descriptions](https://docs.aws.amazon.com/sdkref/latest/guide/maint-policy.html#version-life-cycle) for more information.

## Overview

The Amazon S3 Transfer Manager for Swift (S3TM for short) is a high-level library built on top of the [AWS Swift SDK S3 client](https://github.com/awslabs/aws-sdk-swift/blob/main/Sources/Services/AWSS3/Sources/AWSS3/S3Client.swift). It provides an intuitive transfer API for reliable and performant data transfer between your Swift application and Amazon S3, as well as the ability to monitor the progress of the transfers in real-time.

There are 4 transfer operations supported by S3TM:

* Upload a single object
* Download a single object
* Upload a directory
* Download a bucket

As mentioned above, S3TM allows monitoring the progress of all 4 operations above.

## Getting Started

### Add the dependency to your Xcode project

**_TODO AFTER GITHUB REPO CREATION: Add rough outline of steps needed to add the S3TM dependency to an Xcode project_**

### Add the dependency to your Swift package

**_TODO AFTER GITHUB REPO CREATION: Add example Package.swift contents_**

### Initialize the S3 Transfer Manager

You can initialize a S3TM instance with all-default settings by simply doing this:

```swift
// Creates and uses default S3TM config & S3 client.
let s3tm = try await S3TransferManager()
```

Or you could pass the config object to the initializer to customize S3TM by doing this:

```swift
// Create the custom S3 client that you want S3TM to use.
let s3ClientConfig = try await S3Client.S3ClientConfiguration(
    region: "some-region",
    . . . custom S3 client configurations . . .
)
let customS3Client = S3Client(config: s3ClientConfig)

// Create the custom S3TM config with the S3 client initialized above.
let s3tmConfig = try await S3TransferManagerConfig(
    s3Client: customS3Client, // CUstom S3 client is configured here.
    targetPartSizeBytes: 10 * 1024 * 1024, // 10MB part size.
    multipartUploadThresholdBytes: 100 * 1024 * 1024, // 100MB threshold.
    checksumValidationEnabled: true,
    checksumAlgorithm: .crc32,
    multipartDownloadType: .part
)

// Finally, create the S3TM using the custom S3TM config.
let s3tm = S3TransferManager(config: s3tmConfig)
```

For more information on what each configuration does, please refer to these documentation comments on S3TransferManagerConfig. **_TODO AFTER GITHUB REPO CREATION: ADD LINK_**

## Amazon S3 Transfer Manager for Swift usage examples

### Upload an object

To upload a file to Amazon S3, you need to provide the input struct UploadObjectInput, which is a container for the PutObjectInput struct and an array of TransferListener. You must provide the target bucket, the S3 object key to use, and the file body via PutObjectInput members. 

For uploading files bigger than the configured threshold (16MB default), S3TM breaks them down into parts, each with the configured part size, and uploads them concurrently using S3’s [multipart upload feature](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html#mpu-process).

```swift
let s3tm = try await S3TransferManager()

// Construct UploadObjectInput.
let putObjectInput = PutObjectInput(
    body: ByteStream.stream(
        FileStream(fileHandle: try FileHandle(forReadingFrom: URL(string: "file-to-upload.txt")!))
    ),
    bucket: "destination-bucket",
    key: "some-key"
)
let uploadObjectInput = UploadObjectInput(
    putObjectInput: putObjectInput,
    transferListeners: [LoggingTransferListener()]
)

// Call .uploadObject and save the returned task.
let uploadObjectTask = try s3tm.uploadObject(input: uploadObjectInput)

// Optional: await on the returned task and retrieve the operation output or an error.
// Even if you don't do this, the task executes in the background.
do {
    let uploadObjectOutput = try await uploadObjectTask.value
} catch {
    // Handle error.
}
```

### Download an object

To download an object from Amazon S3, you need to provide the input struct DownloadObjectInput, which is a container for the download destination, the GetObjectInput struct, and an array of TransferListener. The download destination is an instance of [Swift’s Foundation.OutputStream](https://developer.apple.com/documentation/foundation/outputstream). You must provide the target bucket and the S3 object key via GetObjectInput members. 

For downloading objects bigger than a single part size (8MB default), S3TM concurrently downloads the entire object in parts using part numbers or byte ranges.

```swift
let s3tm = try await S3TransferManager()

// Construct DownloadObjectInput.
let getObjectInput = GetObjectInput(
    bucket: "source-bucket",
    key: "s3-object.txt"
)
let downloadObjectInput = DownloadObjectInput(
    outputStream: OutputStream(toFileAtPath: "destination-file.txt", append: true)!,
    getObjectInput: getObjectInput
)

// Call .downloadObject and save the returned task.
let downloadObjectTask = try s3tm.downloadObject(input: downloadObjectInput)

// Optional: await on the returned task and retrieve the operation output or an error.
// Even if you don't do this, the task executes in the background.
do {
    let downloadObjectOutput = try await downloadObjectTask.value
} catch {
    // Handle error.
}
```

### Upload a directory

To upload a local directory to Amazon S3, you need to provide the input struct UploadDirectoryInput and provide the target bucket, and the source directory’s URL. 

The UploadDirectoryInput struct has several optional properties that configure the transfer behavior. For more details on what each input configuration does, refer to these documentation comments on the UploadDirectoryInput initializer. **_TODO AFTER GITHUB REPO CREATION: ADD LINK_**

```swift
let s3tm = try await S3TransferManager()

// Construct UploadDirectoryInput.
let uploadDirectoryInput = try UploadDirectoryInput(
    bucket: "destination-bucket",
    source: URL(string: "source/directory/to/upload")!
)

// Call .uploadDirectory and save the returned task.
let uploadDirectoryTask = try s3tm.uploadDirectory(input: uploadDirectoryInput)

// Optional: await on the returned task and retrieve the operation output or an error.
// Even if you don't do this, the task executes in the background.
do {
    let uploadDirectoryOutput = try await uploadDirectoryTask.value
} catch {
    // Handle error.
}
```

### Download a bucket

To download a S3 bucket to a local directory, you need to provide the input struct DownloadBucketInput and provide the source bucket, and the destination directory URL.

The DownloadBucketInput struct has several optional properties that configure the transfer behavior. For more details on what each input configuration does, refer to these documentation comments on the DownloadBucketInput initializer. **_TODO AFTER GITHUB REPO CREATION: ADD LINK_**

```swift
let s3tm = try await S3TransferManager()

// Construct DownloadBucketInput.
let downloadBucketInput = DownloadBucketInput(
    bucket: "source-bucket",
    destination: URL(string: "destination/directory/for/download")!
)

// Call .downloadBucket and save the returned task.
let downloadBucketTask = try s3tm.downloadBucket(input: downloadBucketInput)

// Optional: await on the returned task and retrieve the operation output or an error.
// Even if you don't do this, the task executes in the background.
do {
    let downloadBucketOutput = try await downloadBucketTask.value
} catch {
    // Handle error.
}
```

### Monitor transfer progress

You can optionally configure transfer listeners for any of the S3TM operations above. The Amazon S3 Transfer Manager for Swift provides 2 canned transfer progress listeners for you. They’re LoggingTransferListener and StreamingTransferListener. 

The LoggingTransferListener logs transfer events to the console (or some other configured location) using [swift-log](https://github.com/apple/swift-log). The StreamingTransferListener publishes transfer events to its AsyncThrowingStream instance property, which can be awaited on to consume and handle events as needed. You can configure any number of transfer listeners for the S3TM operations via their inputs (e.g., UploadObject.transferListeners). You can add your own custom transfer listeners as well, by implementing a struct or a class that conforms to the TransferListener protocol and configuring it in the input structs.

See below for the example usage of the two canned transfer listeners.

#### LoggingTransferListener

```swift
// Assume s3tm: S3TransferManager & putObjectInput: PutObjectInput are initialized.

let uploadObjectInput = UploadObjectInput(
    putObjectInput: putObjectInput,
    transferListeners: [LoggingTransferListener()]
)

// Call .uploadObject and save the returned task.
let uploadObjectTask = try s3tm.uploadObject(input: uploadObjectInput)

// Task will output real-time upload transfer progress to the console as it executes.
```

#### StreamingTransferListener

For StreamingTransferListener, you must close the underlying AsyncThrowingStream by explicitly calling closeStream() on the StreamingTransferListener instance to prevent memory leaks and hanging customers.

```swift
let s3tm = try await S3TransferManager()
        
// Create the StreamingTransferListener.
let streamingTransferListener = StreamingTransferListener()

// Start up the background Task that consumes events from the stream.
Task {
    for try await event in streamingTransferListener.stream {
        switch event {
        case .uploadObjectInitiated(let input, let snapshot):
            print("UploadObject operation initiated. ID: \(input.operationID)")
        case .uploadObjectBytesTransferred(let input, let snapshot):
            print("Transferred more bytes. Running total: \(snapshot.transferredBytes)")
        case .uploadObjectComplete(let input, let output, let snapshot):
            print("Successfully finished UploadObject. ID: \(input.operationID)")
            streamingTransferListener.closeStream() // Close stream explicitly if it won't be used anymore.
        case .uploadObjectFailed(let input, let snapshot):
            print("UploadObject failed. ID: \(input.operationID)")
            streamingTransferListener.closeStream() // Close stream explicitly if it won't be used anymore.
        default:
            break
        }
    }
}

let fileToUpload = URL(string: "file-to-upload.txt")!
// Invoke the transfer manager operation with the streaming transfer listener configured in the input.
let uploadObjectTask = try s3tm.uploadObject(input: UploadObjectInput(
    putObjectInput: PutObjectInput(
        body: ByteStream.stream(FileStream(fileHandle: FileHandle(forReadingFrom: fileToUpload))),
            bucket: "destination-bucket",
        key: "some-key"
    ),
    transferListeners: [streamingTransferListener]
))

// Task will output real-time upload transfer progress to the console as it executes.
```

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the Apache-2.0 License.

