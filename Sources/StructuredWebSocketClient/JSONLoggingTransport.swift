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
    private let formatJSON: Bool
    public let nextIn: WebSocketMessageInboundMiddleware?
    public let nextOut: WebSocketMessageOutboundMiddleware?

    public init(
        formatJSON: Bool = false,
        nextIn: WebSocketMessageInboundMiddleware?,
        nextOut: WebSocketMessageOutboundMiddleware?,
        logger: Logger? = nil
    ) {
        self.formatJSON = formatJSON
        self.nextIn = nextIn
        self.nextOut = nextOut
        self.logger = logger ?? Logger(label: "JSONLoggingTransport")
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message, metadata: MessageMetadata) async throws -> MessageHandling {
        if logger.logLevel == .trace {
            if formatJSON {
                let json = try JSONSerialization.jsonObject(with: try received.data())
                let data = try JSONSerialization.data(withJSONObject: json, options: [])
                logger.trace("⬇︎: \(String(decoding: data, as: UTF8.self))")
            } else {
                logger.trace("⬇︎ \(metadata.number): \((try? received.string()) ?? "")")
            }
        }
        
        if let nextIn { return try await nextIn.handle(received, metadata: metadata) }
        else { return .unhandled(received) }
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message? {
        if logger.logLevel == .trace {
            if formatJSON {
                let json = try JSONSerialization.jsonObject(with: try message.data())
                let data = try JSONSerialization.data(withJSONObject: json, options: [])
                logger.trace("⬆︎: \(String(decoding: data, as: UTF8.self))")
            } else {
                logger.trace("⬆︎: \((try? message.string()) ?? "")")
            }
        }
        
        if let nextOut { return try await nextOut.send(message) }
        else { return message }
    }
}
