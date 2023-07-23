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
    public var events: AsyncThrowingChannel<WebSocketClient.WebSocketEvents, Error> = .init()
    private var awaiter: Awaiter = .init()
    
    public init(initialMessages: [URLSessionWebSocketTask.Message] = []) {
        Task {
            for message in initialMessages {
                await self.push(.message(message))
            }
            // here we should trigger the awaiter to enter the escond waiting phase
        }
    }
    
    // will wait until state is connected
    public func push(_ event: WebSocketClient.WebSocketEvents) async {
        print("awaiting connection")
        await awaiter.awaitUntilMet {
            print("Sending event")
            await self.events.send(event)
        }
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        // TODO: allow assertions on sent/encoded messages
        // print("Sending: \(String(decoding: try message.data(), as: UTF8.self))")
    }
    
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task {
            await events.send(.state(.disconnected))
            self.events.finish()
        }
    }
    
    public func resume() {
        Task {
            await events.send(.state(.connected))
            print("condition is met")
            await awaiter.trigger()
        }
    }
}

public final class NoOpMiddleWare: WebSocketMessageMiddleware {
    public var next: (StructuredWebSocketClient.WebSocketMessageMiddleware)? { nil }
    
    public init() {}
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await next?.send(message)
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message? {
        return received
    }
}
