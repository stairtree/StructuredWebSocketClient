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

public final class WebSocketClient {
    public enum State: Equatable, Hashable {
        case disconnecting, disconnected, connecting, connected
    }
    
    private var _state: State = .disconnected {
        didSet {
            guard _state != oldValue else { return }
//            stateContinuation.yield(_state)
        }
    }
    
    public enum WebSocketEvents {
        case state(State)
        case message(URLSessionWebSocketTask.Message)
    }
    
    public let events: AsyncChannel<WebSocketEvents>
    
    public let label: String
    private let logger: Logger
    internal let transport: MessageTransport
    internal let middleware: WebSocketMessageMiddleware?
    
    public init(
        label: String = "",
        middleware: WebSocketMessageMiddleware?,
        transport: MessageTransport,
        logger: Logger? = nil
    ) {
        self.label = label
        self.transport = transport
        self.middleware = middleware
        self.logger = logger ?? Logger(label: label)
        self.events = .init()
    }
    
    deinit {
        self.logger.trace("♻️ Deinit of WebSocketClient")
    }
    
    public func connect() async {
        _state = .connecting
        transport.resume()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await transportEvent in self.transport.events {
                        switch transportEvent {
                        case let .state(s):
                            self._state = s
                            await self.events.send(.state(s))
                        case let .message(m):
                            // pipe message through middleware
                            if let middleware = self.middleware {
                                if let handled = try await middleware.handle(m) {
                                    await self.events.send(.message(handled))
                                }
                            } else {
                                await self.events.send(.message(m))
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
    
    public func disconnect(reason: String?) {
        _state = .disconnecting
        transport.cancel(with: .normalClosure, reason: Data(reason?.utf8 ?? "Closing connection".utf8))
    }
    
    public func sendMessage(_ message: URLSessionWebSocketTask.Message) async throws {
        try await transport.send(message)
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
}
