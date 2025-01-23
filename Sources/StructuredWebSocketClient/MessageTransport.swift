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
import Logging
import AsyncAlgorithms
#if canImport(FoundationNetworking)
@preconcurrency import FoundationNetworking
#endif

public protocol MessageTransport: Sendable {
    /// Connect the transport
    /// - Returns: An async sequence of events. This includes state changes and messages.
    func connect() -> AsyncChannel<WebSocketEvent>
    /// Emit an outbound message
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    /// Close the websocket
    func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

public enum MessageHandling: Sendable {
    case handled, unhandled(URLSessionWebSocketTask.Message)
}

public struct MessageMetadata: Sendable {
    /// The increasing number of the message
    public let number: Int
    /// The uptimenanoseconds the message was received from the network
    public let receivedAt: Date
    
    public init(number: Int, receivedAt: Date = .init()) {
        self.number = number
        self.receivedAt = receivedAt
    }
}

public protocol WebSocketMessageInboundMiddleware: Sendable {
    /// The next middleware in the chain
    var nextIn: (any WebSocketMessageInboundMiddleware)? { get }
    /// Handle an incoming message
    ///
    /// If the middleware handled the message, it must return `.handled`. Otherwise, the client will emit
    /// the message as `.message` event in its events channel. The middleware may also just repackage
    /// the message and hand it back to the client.
    func handle(_ received: URLSessionWebSocketTask.Message, metadata: MessageMetadata) async throws -> MessageHandling
}

public protocol WebSocketMessageOutboundMiddleware: Sendable {
    /// The next middleware on the way out
    var nextOut: (any WebSocketMessageOutboundMiddleware)? { get }
    /// Emit an outbound message
    func send(_ message: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message?
}
