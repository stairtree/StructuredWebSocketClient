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
    private var connectedContinuation: CheckedContinuation<Void, Never>?
    
    public init() {}
    
    // will wait until state is connected
    public func push(_ event: WebSocketClient.WebSocketEvents) async {
        print("awaiting connection")
        await withCheckedContinuation { continuation in
            if connectedContinuation == nil {
                connectedContinuation = continuation
            }
        }
        await self.events.send(event)
    }
    
    public var events: AsyncThrowingChannel<WebSocketClient.WebSocketEvents, Error> = .init()
    
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
            if let connectedContinuation {
                print("resuming with connection")
                connectedContinuation.resume()
            }
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
