// swift-tools-version:6.3
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

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("AsyncCallerExecution"),
    .enableUpcomingFeature("ExistentialAny"),
    // .enableUpcomingFeature("InternalImportsByDefault"),
    // .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
]

let package = Package(
    name: "StructuredWebSocketClient",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(name: "StructuredWebSocketClient", targets: ["StructuredWebSocketClient"]),
        .library(name: "StructuredWebSocketClientTestSupport", targets: ["StructuredWebSocketClientTestSupport"]),
    ],
    dependencies: [
        // Swift logging API
        .package(url: "https://github.com/apple/swift-log.git", from: "1.11.0"),
        // AsyncChannel with backpressure
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "StructuredWebSocketClient",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "StructuredWebSocketClientTestSupport",
            dependencies: [
                .target(name: "StructuredWebSocketClient"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "StructuredWebSocketClientTests",
            dependencies: [
                .target(name: "StructuredWebSocketClient"),
                .target(name: "StructuredWebSocketClientTestSupport"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
