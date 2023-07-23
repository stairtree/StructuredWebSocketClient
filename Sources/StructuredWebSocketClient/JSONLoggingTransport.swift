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

import Foundation
import AsyncAlgorithms
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Assumes messages containing JSON and logs them
public final class JSONLoggingTransport: WebSocketMessageMiddleware {
    
    private let logger: Logger
    let label: String
    public let next: WebSocketMessageMiddleware?
    
    public init(label: String, next: WebSocketMessageMiddleware, logger: Logger? = nil) {
        self.label = label
        self.next = next
        self.logger = logger ?? Logger(label: label)
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message? {
        let json = try JSONSerialization.jsonObject(with: try received.data())
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        logger.debug("⬇︎: \(String(decoding: data, as: UTF8.self))")
        return try await next?.handle(received)
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        let json = try JSONSerialization.jsonObject(with: try message.data())
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        logger.debug("⬆︎: \(String(decoding: data, as: UTF8.self))")
        try await next?.send(message)
    }
}
