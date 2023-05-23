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

public final class InterceptingTransport: MessageTransport {
    
    public enum Handling {
        case handled, unhandled(URLSessionWebSocketTask.Message)
    }
    
    let base: MessageTransport
    let _handle: (_ message: URLSessionWebSocketTask.Message) async throws -> Handling
    
    public init(
        base: MessageTransport,
        handle: @escaping (_ message: URLSessionWebSocketTask.Message) async throws -> Handling
    ) {
        self.base = base
        self._handle = handle
    }
    
    public var transportDelegate: MessageTransportDelegate? {
        get { base.transportDelegate }
        set { base.transportDelegate = newValue }
    }
    
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        try await base.receive()
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) async throws {
        switch try await self._handle(received) {
        case .handled:
            ()
        case .unhandled(let message):
            try await base.handle(message)
        }
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await base.send(message)
    }
    
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        base.cancel(with: closeCode, reason: reason)
    }
    
    public func resume() {
        base.resume()
    }
}
