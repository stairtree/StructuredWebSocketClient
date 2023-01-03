//===----------------------------------------------------------------------===//
//
// This source file is part of the CodableWebSocket open source project
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
import WebSocketClient

public final class TestMessageTransport: MessageTransport {
    public var transportDelegate: MessageTransportDelegate?
    private var stream: AsyncStream<URLSessionWebSocketTask.Message>!
    private var continuation: AsyncStream<URLSessionWebSocketTask.Message>.Continuation!
    private var iterator: AsyncStream<URLSessionWebSocketTask.Message>.Iterator!
    
    public init(initialResponses: [URLSessionWebSocketTask.Message] = []) {
        self.stream = .init { self.continuation = $0 }
        self.iterator = self.stream.makeAsyncIterator()
        for response in initialResponses { self.continuation.yield(response) }
    }
    
    public func push(_ response: URLSessionWebSocketTask.Message) async {
        self.continuation.yield(response)
    }
    
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        guard let response = await self.iterator.next() else { throw CancellationError() }
        return response
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        // TODO: allow assertions on sent/encoded messages
        // print("Sending: \(String(decoding: try message.data(), as: UTF8.self))")
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) throws -> URLSessionWebSocketTask.Message? {
        received
    }
    
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        continuation.finish()
    }
    
    public func resume() {
        //
    }
}
