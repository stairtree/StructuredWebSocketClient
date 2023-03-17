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

public final class URLSessionWebSocketTransport: MessageTransport {
    private let task: URLSessionWebSocketTask
    private var delegateHandler: WebSocketTaskDelegateHandler!
    // set by the consumer
    public var transportDelegate: MessageTransportDelegate?
    
    public init(request: URLRequest, urlSession: URLSession = .shared) {
        self.task = urlSession.webSocketTask(with: request)
        self.delegateHandler = WebSocketTaskDelegateHandler { [weak self] `protocol` in
            self?.transportDelegate?.didOpenWithProtocol(`protocol`)
        } onClose: { [weak self] closeCode, reason in
            self?.transportDelegate?.didCloseWith(closeCode: closeCode, reason: reason)
        }
        self.task.delegate = self.delegateHandler
    }
    
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        try await task.receive()
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await task.send(message)
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) throws {
        
    }

    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task.cancel(with: closeCode, reason: reason)
    }
    
    public func resume() {
        task.resume()
    }
}
