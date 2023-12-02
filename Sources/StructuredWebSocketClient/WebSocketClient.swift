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
import Logging
import AsyncAlgorithms
#if canImport(FoundationNetworking)
@preconcurrency import FoundationNetworking
#endif

public enum WebSocketEvent: Sendable {
    case state(WebSocketClient.State)
    case message(URLSessionWebSocketTask.Message, metadata: MessageMetadata)
    case failure(Error)
}

public final class WebSocketClient: Sendable {
    public enum State: Hashable, Sendable {
        case connected, disconnected(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    }
    
    private let logger: Logger
    internal let transport: any MessageTransport
    internal let inboundMiddleware: WebSocketMessageInboundMiddleware?
    internal let outboundMiddleware: WebSocketMessageOutboundMiddleware?

    public init(
        inboundMiddleware: WebSocketMessageInboundMiddleware?,
        outboundMiddleware: WebSocketMessageOutboundMiddleware?,
        transport: any MessageTransport,
        logger: Logger? = nil
    ) {
        self.transport = transport
        self.inboundMiddleware = inboundMiddleware
        self.outboundMiddleware = outboundMiddleware
        self.logger = logger ?? Logger(label: "WebSocketClient")
    }
    
    public func connect() -> AsyncCompactMapSequence<AsyncChannel<WebSocketEvent>, WebSocketEvent> {
        let inboundMiddleware = self.inboundMiddleware
        let logger = self.logger
        
        return self.transport.connect().compactMap { e -> WebSocketEvent? in
            switch e {
            case let .state(s):
                return .state(s)
            case let .message(m, metadata: meta):
                // pipe message through middleware
                if let middleware = inboundMiddleware {
                    do {
                        let handled = try await middleware.handle(m, metadata: meta)
                        switch handled {
                        case .handled:
                            return nil
                        case let .unhandled(unhandled):
                            return.message(unhandled, metadata: meta)
                        }
                    } catch {
                        logger.error("\(error)")
                        // In case the middleware throws when handling the message
                        // We could also just pretend it was unhandled.
                        return .failure(error)
                    }
                } else {
                    return .message(m, metadata: meta)
                }
            case let .failure(error):
                logger.error("\(error)")
                return .failure(error)
            }
        }
    }
    
    public func disconnect(reason: String?) async {
        self.transport.close(with: .normalClosure, reason: Data(reason?.utf8 ?? "Closing connection".utf8))
    }
    
    /// Pass the message through all the middleware, and then send it via the transport (if it hasn't been swallowed by middleware)
    public func sendMessage(_ message: URLSessionWebSocketTask.Message) async throws {
        if let outboundMiddleware {
            if let msg = try await outboundMiddleware.send(message) {
                try await self.transport.send(msg)
            }
        } else {
            try await self.transport.send(message)
        }
    }
}

extension WebSocketEvent: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .state(s):
            return "\(s)"
        case let .message(msg, metadata: meta):
            return "'\(msg)', metadata: \(meta)"
        case let .failure(error):
            return "error(\(error))"
        }
    }
}

public enum WebSocketError: Error {
    case unknownMessageFormat
    case notUTF8String
}

extension URLSessionWebSocketTask.Message {
    public func data() throws -> Data {
        switch self {
        case let .data(data):
            return data
        case let .string(text):
            return Data(text.utf8)
        #if canImport(Darwin)
        @unknown default:
            throw WebSocketError.unknownMessageFormat
        #endif
        }
    }
    
    public func string() throws -> String {
        switch self {
        case let .data(data):
            if let str = String(data: data, encoding: .utf8) {
                return str
            } else {
                throw WebSocketError.notUTF8String
            }
        case let .string(text):
            return text
        #if canImport(Darwin)
        @unknown default:
            throw WebSocketError.unknownMessageFormat
        #endif
        }
    }
}
