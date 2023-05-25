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
import StructuredWebSocketClient

public final class TestMessageTransport: MessageTransport {
    public var transportDelegate: MessageTransportDelegate?
    public var stream: AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>!
    private var continuation: AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>.Continuation!
    private var iterator: AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>.Iterator!
    
    public init(initialResponses: [URLSessionWebSocketTask.Message] = []) {
        self.stream = .init { self.continuation = $0 }
        self.iterator = self.stream.makeAsyncIterator()
        for response in initialResponses { self.continuation.yield(response) }
    }
    
    public func push(_ response: URLSessionWebSocketTask.Message) async {
        self.continuation.yield(response)
    }
    
    public var messages: WebSocketStream { stream }
    
//    public func receive() async throws -> URLSessionWebSocketTask.Message {
//        guard let response = try await self.iterator.next() else { throw CancellationError() }
//        return response
//    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        // TODO: allow assertions on sent/encoded messages
        // print("Sending: \(String(decoding: try message.data(), as: UTF8.self))")
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) throws {
        //
    }
    
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        continuation.finish()
    }
    
    public func resume() {
        //
    }
}
