// swift-tools-version: 5.9

import Foundation
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
    dependencies: runtimeDependencies,
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

private var runtimeDependencies: [Package.Dependency] {
    let smithySwiftLocal = "../smithy-swift"
    let smithySwiftGitURL = "https://github.com/smithy-lang/smithy-swift"

    let awsSDKSwiftLocal = "../aws-sdk-swift"
    let awsSDKSwiftGitURL = "https://github.com/awslabs/aws-sdk-swift.git"

    let useLocalDeps = ProcessInfo.processInfo.environment["AWS_SWIFT_SDK_S3TM_USE_LOCAL_DEPS"] != nil

    if useLocalDeps {
        return [
            .package(path: smithySwiftLocal),
            .package(path: awsSDKSwiftLocal)
        ]
    } else {
        return [
            .package(url: smithySwiftGitURL, from: "0.146.0"),
            .package(url: awsSDKSwiftGitURL, from: "1.5.0")
        ]
    }
}
