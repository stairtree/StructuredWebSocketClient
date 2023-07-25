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
import FoundationNetworking
#endif

public enum WebSocketEvents: Sendable {
    case state(WebSocketClient.State)
    case message(URLSessionWebSocketTask.Message, metadata: MessageMetadata)
}

public final class WebSocketClient {
    public enum State: Hashable, Sendable {
        case disconnecting, disconnected, connecting, connected
    }
    
    private var _state: State = .disconnected
    
    public let events: AsyncChannel<WebSocketEvents>
    
    public let label: String
    private let logger: Logger
    internal let transport: MessageTransport
    internal let inboundMiddleware: WebSocketMessageInboundMiddleware?
    internal let outboundMiddleware: WebSocketMessageOutboundMiddleware?

    public init(
        label: String = "",
        inboundMiddleware: WebSocketMessageInboundMiddleware?,
        outboundMiddleware: WebSocketMessageOutboundMiddleware?,
        transport: MessageTransport,
        logger: Logger? = nil
    ) {
        self.label = label
        self.transport = transport
        self.inboundMiddleware = inboundMiddleware
        self.outboundMiddleware = outboundMiddleware
        self.logger = logger ?? Logger(label: label)
        self.events = .init()
    }
    
    deinit {
        self.logger.trace("♻️ Deinit of WebSocketClient")
    }
    
    private func setState(to newState: State) async {
        let oldValue = self._state
        self._state = newState
        guard _state != oldValue else { return }
        await events.send(.state(self._state))
    }
    
    public func connect() async {
        await self.setState(to: .connecting)

        transport.resume()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await transportEvent in self.transport.events {
                        switch transportEvent {
                        case let .state(s):
                            await self.setState(to: s)
                        case let .message(m, metadata: meta):
                            // pipe message through middleware
                            if let middleware = self.inboundMiddleware {
                                let handled = try await middleware.handle(m, metadata: meta)
                                switch handled {
                                case .handled:
                                    ()
                                case let .unhandled(unhandled):
                                    await self.events.send(.message(unhandled, metadata: meta))
                                }
                            } else {
                                await self.events.send(.message(m, metadata: meta))
                            }
                        }
                    }
                    self.logger.info("Transport events ended")
                    self.events.finish()
                }
                try await group.next()
            }
        } catch {
            logger.error("> \(error)")
        }
    }
    
    public func disconnect(reason: String?) async {
        await self.setState(to: .disconnecting)
        transport.cancel(with: .normalClosure, reason: Data(reason?.utf8 ?? "Closing connection".utf8))
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

public enum WebSocketError: Error {
    case unknownMessageFormat
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
    
    public func text() throws -> String {
        switch self {
        case let .data(data):
            return String(decoding: data, as: UTF8.self)
        case let .string(text):
            return text
        @unknown default:
            throw WebSocketError.unknownMessageFormat
        }
    }
}
