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

public protocol MessageTransport {
    /// The stream of events.
    /// The stream must be closed once the transport is cancelled, or closed otherwise.
    var events: AsyncThrowingChannel<WebSocketEvents, Error> { get }
    /// Emit an outbound message
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func resume()
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


// MARK: - WebSocketTaskDelegate

public final class WebSocketTaskDelegateHandler: NSObject {
    let onOpen: (_ `protocol`: String?) async -> Void
    let onClose: (_ closeCode: URLSessionWebSocketTask.CloseCode, _ reason: Data?) async -> Void
    
    init(onOpen: @escaping (_ `protocol`: String?) async -> Void, onClose: @escaping (_ closeCode: URLSessionWebSocketTask.CloseCode, _ reason: Data?) async -> Void) {
        self.onOpen = onOpen
        self.onClose = onClose
    }
    
    public func didOpenWithProtocol(_ protocol: String?) async {
        await onOpen(`protocol`)
    }
    
    public func didCloseWith(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async {
        await onClose(closeCode ,reason)
    }
}

extension WebSocketTaskDelegateHandler: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { await didOpenWithProtocol(`protocol`) }
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { await didCloseWith(closeCode: closeCode, reason: reason) }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Timeout
        if let nsError = error as? NSError, nsError.code == 60 {
            Task {
                await onClose(
                    .abnormalClosure,
                    nsError.localizedFailureReason.map { Data($0.utf8) } ?? Data(nsError.localizedDescription.utf8)
                )
            }
        }
        // We don't want to call onClose again here, as we'd call it twice then.
        // TODO: Figure out when we'd get this callback but not `WebSocketTaskDelegateHandler.urlSession(_:webSocketTask:didCloseWith:reason:)`
    }
}
