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
    public let nextIn: (any WebSocketMessageInboundMiddleware)?
    let _handle: @Sendable (_ message: URLSessionWebSocketTask.Message) async throws -> MessageHandling
    
    public init(
        next: (any WebSocketMessageInboundMiddleware)?,
        handle: @escaping @Sendable (_ message: URLSessionWebSocketTask.Message) async throws -> MessageHandling
    ) {
        self.nextIn = next
        self._handle = handle
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message, metadata: MessageMetadata) async throws -> MessageHandling {
        switch try await self._handle(received) {
        case .handled: return .handled
        case .unhandled(let message):
            if let nextIn { return try await nextIn.handle(message, metadata: metadata) }
            return .unhandled(message)
        }
    }
}
