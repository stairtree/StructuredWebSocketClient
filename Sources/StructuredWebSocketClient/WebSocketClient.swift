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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WebSocketEvent: Sendable {
    case state(WebSocketClient.State)
    case message(URLSessionWebSocketTask.Message, metadata: MessageMetadata)
}

public final class WebSocketClient {
    public enum State: Hashable, Sendable {
        case connected, disconnected
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
    
    deinit {
        self.logger.trace("♻️ Deinit of WebSocketClient")
    }
    
    public func connect() -> AnyAsyncSequence<WebSocketEvent> {
        self.transport.connect().compactMap { e -> WebSocketEvent? in
            switch e {
            case let .state(s):
                return .state(s)
            case let .message(m, metadata: meta):
                // pipe message through middleware
                if let middleware = self.inboundMiddleware {
                    let handled = try await middleware.handle(m, metadata: meta)
                    switch handled {
                    case .handled:
                        return nil
                    case let .unhandled(unhandled):
                        return.message(unhandled, metadata: meta)
                    }
                } else {
                    return .message(m, metadata: meta)
                }
            }
        }.eraseToAnyAsyncSequence()
    }
    
    public func disconnect(reason: String?) async {
        transport.close(with: .normalClosure, reason: Data(reason?.utf8 ?? "Closing connection".utf8))
    }
    
    /// Pass the message through all the middleware, and then send it via the transport (if it hasn't been swallowed by middleware)
    public func sendMessage(_ message: URLSessionWebSocketTask.Message) async throws {
        if let outboundMiddleware {
            if let msg = try await outboundMiddleware.send(message) {
                try await transport.send(msg)
            }
        } else {
            try await transport.send(message)
        }
    }
}

extension WebSocketEvent: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .state(s):
            "\(s)"
        case let .message(msg, metadata: meta):
            "'\(msg)', metadata: \(meta)"
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
        @unknown default:
            throw WebSocketError.unknownMessageFormat
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
        @unknown default:
            throw WebSocketError.unknownMessageFormat
        }
    }
}
