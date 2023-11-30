// swift-tools-version:5.9
//===----------------------------------------------------------------------===//
//
// This source file is part of the StructuredWebSocketClient open source project
//
// Copyright (c) Stairtree GmbH
// Licensed under the MIT license
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "StructuredWebSocketClient",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .watchOS(.v8),
        .tvOS(.v15),
    ],
    products: [
        .library(name: "StructuredWebSocketClient", targets: ["StructuredWebSocketClient"]),
        .library(name: "StructuredWebSocketClientTestSupport", targets: ["StructuredWebSocketClientTestSupport"]),
    ],
    dependencies: [
        // Swift logging API
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.2"),
        // AsyncChannel with backpressure
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0-beta.1"),
    ],
    targets: [
        .target(
            name: "StructuredWebSocketClient",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]
        ),
        .target(
            name: "StructuredWebSocketClientTestSupport",
            dependencies: [
                .target(name: "StructuredWebSocketClient"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]
        ),
        .testTarget(
            name: "StructuredWebSocketClientTests",
            dependencies: [
                .target(name: "StructuredWebSocketClient"),
                .target(name: "StructuredWebSocketClientTestSupport"),
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency=complete")]
        ),
    ]
)
