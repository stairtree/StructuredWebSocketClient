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
public final class JSONLoggingTransport: WebSocketMessageInboundMiddleware, WebSocketMessageOutboundMiddleware {
    
    private let logger: Logger
    let label: String
    public let nextIn: WebSocketMessageInboundMiddleware?
    public let nextOut: WebSocketMessageOutboundMiddleware?

    public init(
        label: String,
        nextIn: WebSocketMessageInboundMiddleware?,
        nextOut: WebSocketMessageOutboundMiddleware?,
        logger: Logger? = nil
    ) {
        self.label = label
        self.nextIn = nextIn
        self.nextOut = nextOut
        self.logger = logger ?? Logger(label: label)
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message? {
        let json = try JSONSerialization.jsonObject(with: try received.data())
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        logger.debug("⬇︎: \(String(decoding: data, as: UTF8.self))")
        return try await nextIn?.handle(received)
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message? {
        let json = try JSONSerialization.jsonObject(with: try message.data())
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        logger.debug("⬆︎: \(String(decoding: data, as: UTF8.self))")
        if let nextOut {
            return try await nextOut.send(message)
        }
        return message
    }
}
