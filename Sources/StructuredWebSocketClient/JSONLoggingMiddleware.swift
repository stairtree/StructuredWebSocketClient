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
public final class JSONLoggingMiddleware: WebSocketMessageInboundMiddleware, WebSocketMessageOutboundMiddleware {
    public typealias Formatting = (reading: JSONSerialization.ReadingOptions, output: JSONSerialization.WritingOptions)
    
    private let logger: Logger?
    private let loggingLevel: Logger.Level
    private let formattingOptions: Formatting?
    public let nextIn: (any WebSocketMessageInboundMiddleware)?
    public let nextOut: (any WebSocketMessageOutboundMiddleware)?

    public init(
        logger: Logger? = nil,
        loggingLevel: Logger.Level = .trace,
        formattingOptions: Formatting? = (reading: [.fragmentsAllowed], output: [.withoutEscapingSlashes]),
        nextIn: (any WebSocketMessageInboundMiddleware)?,
        nextOut: (any WebSocketMessageOutboundMiddleware)?
    ) {
        self.logger = logger
        self.loggingLevel = loggingLevel
        self.formattingOptions = formattingOptions
        self.nextIn = nextIn
        self.nextOut = nextOut
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message, metadata: MessageMetadata) async throws -> MessageHandling {
        if let logger = self.logger, logger.logLevel <= self.loggingLevel {
            if let formattingOptions = self.formattingOptions, let outData = try? received.data(),
               let json = try? JSONSerialization.jsonObject(with: outData, options: formattingOptions.reading),
               let data = try? JSONSerialization.data(withJSONObject: json, options: formattingOptions.output)
            {
                logger.log(level: self.loggingLevel, "⬇︎: \(String(decoding: data, as: UTF8.self))")
            } else {
                logger.log(level: self.loggingLevel, "⬇︎: \((try? received.string()) ?? "")")
            }
        }
        
        return try await self.nextIn?.handle(received, metadata: metadata) ?? .unhandled(received)
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message? {
        if let logger = self.logger, logger.logLevel <= self.loggingLevel {
            if let formattingOptions = self.formattingOptions, let outData = try? message.data(),
               let json = try? JSONSerialization.jsonObject(with: outData, options: formattingOptions.reading),
               let data = try? JSONSerialization.data(withJSONObject: json, options: formattingOptions.output)
            {
                logger.log(level: self.loggingLevel, "⬆︎: \(String(decoding: data, as: UTF8.self))")
            } else {
                logger.log(level: self.loggingLevel, "⬆︎: \((try? message.string()) ?? "")")
            }
        }
        
        return try await self.nextOut?.send(message) ?? message
    }
}
