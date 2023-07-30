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

actor Awaiter {
    enum State {
        case waiting(waiters: [CheckedContinuation<Void, Never>])
        case ready
    }
    private var state: State = .waiting(waiters: [])
    
    private func addToWaiters() async {
        switch state {
        case .ready:
            return
        case var .waiting(waiters: waiters):
            await withCheckedContinuation { cont in
                waiters.append(cont)
                state = .waiting(waiters: waiters)
            }
        }
    }
    
    func trigger() {
        guard case .waiting(waiters: var waiters) = self.state else {
            fatalError("Exiting in invalid state")
        }
        
        if waiters.isEmpty {
            self.state = .ready
            return
        }

        while !waiters.isEmpty {
            let nextWaiter = waiters.removeFirst()
            self.state = .waiting(waiters: waiters)
            nextWaiter.resume()
        }
        state = .ready
    }
    
    func awaitUntilMet(_ block: @escaping () async throws -> Void) async rethrows {
        await self.addToWaiters()
        try await block()
    }
}

public final class TestMessageTransport: MessageTransport {
    var messageNumber: Int = 0
    private var events: AsyncThrowingChannel<WebSocketEvent, Error> = .init()
    private var awaiter: Awaiter = .init()
    private var _initialMessages: [WebSocketEvent]
    
    public init(initialMessages: [URLSessionWebSocketTask.Message] = []) {
        _initialMessages = initialMessages.enumerated().map { .message($1, metadata: .init(number: $0 + 1)) }
    }
    
    // will wait until state is connected
    public func push(_ event: WebSocketEvent) async {
        await awaiter.awaitUntilMet {
            await self.events.send(event)
        }
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        // TODO: allow assertions on sent/encoded messages
        // print("Sending: \(String(decoding: try message.data(), as: UTF8.self))")
    }
    
    public func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task {
            await events.send(.state(.disconnected))
            self.events.finish()
        }
    }
    
    public func connect() -> AnyAsyncSequence<WebSocketEvent> {
        // if push is called before connect this will only send the messages after the return
        Task { await awaiter.trigger() }
        return chain([.state(.connected)].async, _initialMessages.async, events).eraseToAnyAsyncSequence()
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
