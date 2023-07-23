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

public final class InterceptingTransport: WebSocketMessageInboundMiddleware {
    
    public enum Handling {
        case handled, unhandled(URLSessionWebSocketTask.Message)
    }
    
    public let nextIn: WebSocketMessageInboundMiddleware?
    let _handle: (_ message: URLSessionWebSocketTask.Message) async throws -> Handling
    
    public init(
        next: WebSocketMessageInboundMiddleware?,
        handle: @escaping (_ message: URLSessionWebSocketTask.Message) async throws -> Handling
    ) {
        self.nextIn = next
        self._handle = handle
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message? {
        switch try await self._handle(received) {
        case .handled:
            return nil
        case .unhandled(let message):
            return try await nextIn?.handle(message)
        }
    }
}
