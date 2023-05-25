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

public typealias WebSocketStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>

public protocol MessageTransport {
    var transportDelegate: MessageTransportDelegate? { get nonmutating set }
    /// The stream of messages as they arrive.
    /// The stream must be closed once the transport is cancelled, or closed otherwise.
    var messages: WebSocketStream { get }
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func handle(_ received: URLSessionWebSocketTask.Message) async throws
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func resume()
}

public protocol MessageTransportDelegate: AnyObject {
    func didOpenWithProtocol(_ protocol: String?)
    func didCloseWith(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

// MARK: - WebSocketTaskDelegate

@objcMembers
public final class WebSocketTaskDelegateHandler: NSObject, MessageTransportDelegate {
    let onOpen: (_ `protocol`: String?) -> Void
    let onClose: (_ closeCode: URLSessionWebSocketTask.CloseCode, _ reason: Data?) -> Void
    
    init(onOpen: @escaping (_ `protocol`: String?) -> Void, onClose: @escaping (_ closeCode: URLSessionWebSocketTask.CloseCode, _ reason: Data?) -> Void) {
        self.onOpen = onOpen
        self.onClose = onClose
    }
    
    public func didOpenWithProtocol(_ protocol: String?) {
        onOpen(`protocol`)
    }
    
    public func didCloseWith(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onClose(closeCode ,reason)
    }
}

extension WebSocketTaskDelegateHandler: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        didOpenWithProtocol(`protocol`)
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        didCloseWith(closeCode: closeCode, reason: reason)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Timeout
        if let nsError = error as? NSError, nsError.code == 60 {
            onClose(
                .abnormalClosure,
                nsError.localizedFailureReason.map { Data($0.utf8) } ?? Data(nsError.localizedDescription.utf8)
            )
        }
        // We don't want to call onClose again here, as we'd call it twice then.
        // TODO: Figure out when we'd get this callback but not `WebSocketTaskDelegateHandler.urlSession(_:webSocketTask:didCloseWith:reason:)`
    }
}
