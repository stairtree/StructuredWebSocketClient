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
import FoundationNetworking
#endif

public protocol MessageTransport {
    /// Connect the transport
    /// - Returns: An async sequence of events. This includes state changes and messages.
    func connect() -> AsyncChannel<WebSocketEvent>
    /// Emit an outbound message
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    /// Close the websocket
    func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

public protocol MessageTransportDelegate: AnyObject {
    func didOpenWithProtocol(_ protocol: String?)
    func didCloseWith(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

public enum MessageHandling {
    case handled, unhandled(URLSessionWebSocketTask.Message)
}

public struct MessageMetadata: Sendable {
    /// The increasing number of the message
    public var number: Int
    /// The uptimenanoseconds the message was received from the network
    public var receivedAt: DispatchTime
    
    public init(number: Int, receivedAt: DispatchTime = .now()) {
        self.number = number
        self.receivedAt = receivedAt
    }
}

public protocol WebSocketMessageInboundMiddleware {
    /// The next middleware in the chain
    var nextIn: WebSocketMessageInboundMiddleware? { get }
    /// Handle an incoming message
    ///
    /// If the middleware handled the message, it must return `.handled`. Otherwise, the client will emit
    /// the message as `.message` event in its events channel. The middleware may also just repackage
    /// the message and hand it back to the client.
    func handle(_ received: URLSessionWebSocketTask.Message, metadata: MessageMetadata) async throws -> MessageHandling
}

public protocol WebSocketMessageOutboundMiddleware {
    /// The next middleware on the way out
    var nextOut: WebSocketMessageOutboundMiddleware? { get }
    /// Emit an outbound message
    func send(_ message: URLSessionWebSocketTask.Message) async throws -> URLSessionWebSocketTask.Message?
}

