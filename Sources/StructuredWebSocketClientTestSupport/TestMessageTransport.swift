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
import AsyncHelpers
import AsyncAlgorithms
import StructuredWebSocketClient
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class TestMessageTransport: MessageTransport {
    var messageNumber: Int = 0
    private var events: AsyncChannel<WebSocketEvent> = .init()
    private var awaiter: Awaiter = .init()
    private var _initialMessages: [WebSocketEvent]
    private var _onMessage: (URLSessionWebSocketTask.Message, TestMessageTransport) async throws -> Void
    
    public init(initialMessages: [URLSessionWebSocketTask.Message] = [], onMessage: @escaping (URLSessionWebSocketTask.Message, TestMessageTransport) async throws -> Void = { _, _ in }) {
        _initialMessages = initialMessages.enumerated().map { .message($1, metadata: .init(number: $0 + 1)) }
        _onMessage = onMessage
    }
    
    // will wait until state is connected
    public func push(_ event: WebSocketEvent) async {
        await awaiter.awaitUntilTriggered {
            await self.events.send(event)
        }
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await _onMessage(message, self)
        // print("Sending: \(String(decoding: try message.data(), as: UTF8.self))")
    }
    
    public func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task {
            await events.send(.state(.disconnected(closeCode: closeCode, reason: reason)))
            self.events.finish()
        }
    }
    
    public func connect() -> AsyncChannel<WebSocketEvent> {
        // if push is called before connect this will only send the messages after the return
        Task { await awaiter.trigger() }
        Task {
            for await event in chain([.state(.connected)].async, _initialMessages.async, events) {
                await events.send(event)
            }
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
