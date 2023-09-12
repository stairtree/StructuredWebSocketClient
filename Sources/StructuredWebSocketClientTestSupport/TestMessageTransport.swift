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
import StructuredWebSocketClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class TestMessageTransport: MessageTransport {
    var messageNumber: Int = 0
    private var _events: AsyncChannel<WebSocketEvent> = .init()
    private var events: AsyncChannel<WebSocketEvent> = .init()
    private var _initialMessages: [WebSocketEvent]
    private var _onMessage: (URLSessionWebSocketTask.Message, TestMessageTransport) async throws -> Void
    
    public init(initialMessages: [URLSessionWebSocketTask.Message] = [], onMessage: @escaping (URLSessionWebSocketTask.Message, TestMessageTransport) async throws -> Void = { _, _ in }) {
        _initialMessages = initialMessages.enumerated().map { .message($1, metadata: .init(number: $0 + 1)) }
        _onMessage = onMessage
    }
    
    public func push(_ event: WebSocketEvent) async {
        await self._events.send(event)
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await _onMessage(message, self)
    }
    
    public func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task {
            await _events.send(.state(.disconnected(closeCode: closeCode, reason: reason)))
            self._events.finish()
        }
    }
    
    public func connect() -> AsyncChannel<WebSocketEvent> {
        Task { [unowned self] in
            for await event in chain([.state(.connected)].async, self._initialMessages.async, self._events) {
                await self.events.send(event)
            }
            self.events.finish()
        }
        return events
    }
}

public final class NoOpMiddleWare: WebSocketMessageInboundMiddleware, WebSocketMessageOutboundMiddleware {
    public var nextIn: WebSocketMessageInboundMiddleware? { nil }
    public var nextOut: WebSocketMessageOutboundMiddleware? { nil }

    public init() {}
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message? {
        try await nextOut?.send(message)
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message, metadata: StructuredWebSocketClient.MessageMetadata) async throws -> StructuredWebSocketClient.MessageHandling {
        try await nextIn?.handle(received, metadata: metadata) ?? .unhandled(received)
    }
}
