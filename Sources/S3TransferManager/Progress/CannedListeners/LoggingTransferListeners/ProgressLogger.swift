//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

@preconcurrency import protocol Smithy.LogAgent

protocol ProgressLogger {
    var logger: LogAgent { get }
    var operation: String { get }
}

extension ProgressLogger {

    // Helper function that logs provided message with operation name & operation ID prefix.
    func log(
        _ id: String,
        _ message: String
    ) {
        logger.info("[\(operation) ID: \(id)] \(message)")
    }
}
