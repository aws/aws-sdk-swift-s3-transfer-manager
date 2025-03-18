// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "aws-sdk-swift-s3-transfer-manager",
    platforms: [
        .macOS(.v12),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "S3TransferManager",
            targets: ["S3TransferManager"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.2.39"),
        .package(url: "https://github.com/awslabs/smithy-swift.git", from: "0.123.0"),
    ],
    targets: [
        .target(
            name: "S3TransferManager",
            dependencies: [
                .product(name: "AWSS3", package: "aws-sdk-swift"),
                .product(name: "AWSClientRuntime", package: "aws-sdk-swift"),
                .product(name: "Smithy", package: "smithy-swift"),
                .product(name: "SmithyHTTPAPI", package: "smithy-swift"),
                .product(name: "SmithyStreams", package: "smithy-swift"),
                .product(name: "ClientRuntime", package: "smithy-swift")
            ]
        ),
        .target(
            name: "TestUtil",
            dependencies: [ .product(name: "AWSS3", package: "aws-sdk-swift") ]
        ),
        .testTarget(
            name: "TestUtilTests",
            dependencies: [ "TestUtil" ]
        ),
        .testTarget(
            name: "S3TransferManagerUnitTests",
            dependencies: [
                "S3TransferManager",
                "TestUtil",
                .product(name: "AWSS3", package: "aws-sdk-swift"),
                .product(name: "Smithy", package: "smithy-swift"),
                .product(name: "SmithyStreams", package: "smithy-swift"),
            ],
            path: "Tests",
            exclude: [
                "IntegrationTests",
                "ConcurrentIntegrationTests",
                "TestUtilTests"
            ],
            sources: ["HelperFunctionUnitTests"]
        ),
        .testTarget(
            name: "S3TransferManagerIntegrationTests",
            dependencies: [
                "S3TransferManager",
                "TestUtil",
                .product(name: "AWSS3", package: "aws-sdk-swift"),
                .product(name: "Smithy", package: "smithy-swift"),
                .product(name: "SmithyStreams", package: "smithy-swift"),
            ],
            path: "Tests",
            exclude: [
                "HelperFunctionUnitTests",
                "TestUtilTests"
            ],
            sources: [
                "IntegrationTests",
                "ConcurrentIntegrationTests",
            ]
        )
    ]
)
