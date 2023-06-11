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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class URLSessionWebSocketTransport: MessageTransport {
    private var socketStream: SocketStream!
    
    private let task: URLSessionWebSocketTask
    private var delegateHandler: WebSocketTaskDelegateHandler!
    // set by the consumer
    public weak var transportDelegate: MessageTransportDelegate?
    
    public init(request: URLRequest, urlSession: URLSession = .shared) {
        self.task = urlSession.webSocketTask(with: request)
        self.delegateHandler = WebSocketTaskDelegateHandler { [weak self] `protocol` in
            self?.transportDelegate?.didOpenWithProtocol(`protocol`)
        } onClose: { [weak self] closeCode, reason in
            self?.transportDelegate?.didCloseWith(closeCode: closeCode, reason: reason)
        }
        #if canImport(Darwin)
        self.task.delegate = self.delegateHandler
        #endif
        socketStream = SocketStream(task: task)
    }
    
    public var messages: WebSocketStream { socketStream.stream }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await task.send(message)
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) throws {
        // This is supposed to be the final transport in the chain, so no more
        // delegation to another handler.
    }

    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task.cancel(with: closeCode, reason: reason)
        socketStream.cancel()
    }
    
    public func resume() {
        task.resume()
    }
}

/// A wrapper for a `AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>` to
/// ensure cancelling the task also stops waiting for messages.
///
/// See: https://www.donnywals.com/iterating-over-web-socket-messages-with-async-await-in-swift/
private final class SocketStream: AsyncSequence {
    typealias AsyncIterator = WebSocketStream.Iterator
    typealias Element = URLSessionWebSocketTask.Message

    private var continuation: WebSocketStream.Continuation?
    private unowned var task: URLSessionWebSocketTask
    
    fileprivate var stream: WebSocketStream!
    
    init(task: URLSessionWebSocketTask) {
        self.task = task
        stream = WebSocketStream { continuation in
            self.continuation = continuation
            waitForNextValue()
        }
        task.resume()
    }
    
    // Using the callback based version gets around the Task not ever getting
    // released if the user cancels the websocket connection.
    // `try await task.receive()` doesn't throws when cancelled, and waits
    // forever. This is most likely to the fact that the async version is not
    // properly handling cancellation, but is just a callback based method where
    // Swift is automatically providing an async variant.
    private func waitForNextValue() {
        guard task.closeCode == .invalid else {
            continuation?.finish()
            return
        }
        
        task.receive { [weak self] result in
            guard let continuation = self?.continuation else { return }
            do {
                let message = try result.get()
                continuation.yield(message)
                self?.waitForNextValue()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    deinit {
        continuation?.finish()
    }

    func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }

    func cancel() {
        continuation?.finish()
    }
}
