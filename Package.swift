// swift-tools-version:5.7
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
    platforms: [.iOS(.v15), .macOS(.v12), .watchOS(.v8), .tvOS(.v15)],
    products: [
        .library(
            name: "StructuredWebSocketClient",
            targets: ["StructuredWebSocketClient"]),
        .library(
            name: "StructuredWebSocketClientTestSupport",
            targets: ["StructuredWebSocketClientTestSupport"]),
    ],
    dependencies: [
        // Swift logging API
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.5.2")),
    ],
    targets: [
        .target(
            name: "StructuredWebSocketClient",
            dependencies: [.product(name: "Logging", package: "swift-log")]),
        .target(
            name: "StructuredWebSocketClientTestSupport",
            dependencies: [.target(name: "StructuredWebSocketClient")]),
        .testTarget(
            name: "StructuredWebSocketClientTests",
            dependencies: [
                .target(name: "StructuredWebSocketClient"),
                .target(name: "StructuredWebSocketClientTestSupport"),
            ]),
    ]
)
