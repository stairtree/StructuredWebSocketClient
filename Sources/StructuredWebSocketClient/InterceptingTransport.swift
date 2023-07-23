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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class InterceptingTransport: WebSocketMessageMiddleware {
    
    public enum Handling {
        case handled, unhandled(URLSessionWebSocketTask.Message)
    }
    
    public let next: WebSocketMessageMiddleware?
    let _handle: (_ message: URLSessionWebSocketTask.Message) async throws -> Handling
    
    public init(
        next: WebSocketMessageMiddleware?,
        handle: @escaping (_ message: URLSessionWebSocketTask.Message) async throws -> Handling
    ) {
        self.next = next
        self._handle = handle
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message? {
        switch try await self._handle(received) {
        case .handled:
            return nil
        case .unhandled(let message):
            return try await next?.handle(message)
        }
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await next?.send(message)
    }
}
