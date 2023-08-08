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
import AsyncHelpers
import AsyncAlgorithms
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class URLSessionWebSocketTransport: MessageTransport {
    private let logger: Logger
    private let task: URLSessionWebSocketTask
    /// So `URLSessionWebSocketTransport` doesn't have to be an NSObject subclass
    private var delegateHandler: WebSocketTaskDelegateHandler!
    /// Channel will fail if reading a message fails
    private var messages: AsyncThrowingChannel<URLSessionWebSocketTask.Message, Error> = .init()
    /// Will fail if reading a message failed or if the websocket task completes with an error
    private let events: AsyncThrowingChannel<WebSocketEvent, Error> = .init()
    
    public init(request: URLRequest, urlSession: URLSession = .shared, logger: Logger? = nil) {
        self.logger = logger ?? .init(label: "URLSessionWebSocketTransport")
        self.task = urlSession.webSocketTask(with: request)
        self.delegateHandler = WebSocketTaskDelegateHandler(
            logger: self.logger,
            onOpen: { [weak self] `protocol` in
                Task { [weak self] in await self?.onOpen(protocol: `protocol`) }
            },
            onClose: { [weak self] closeCode, reason in
                Task { [weak self] in await self?.onClose(closeCode: closeCode, reason: reason) }
            },
            didCompleteWithError: { [weak self] error in
                Task { [weak self] in await self?.didCompleteWithError(error) }
            }
        )
        #if canImport(Darwin)
        self.task.delegate = self.delegateHandler
        #endif
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await task.send(message)
    }
    
    public func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task.cancel(with: closeCode, reason: reason)
    }
    
    public func connect() -> AnyAsyncSequence<WebSocketEvent> {
        task.resume()
        return events.eraseToAnyAsyncSequence()
    }
    
    // MARK: - Private
    
    private func onOpen(protocol: String?) async {
        await self.events.send(.state(.connected))
        // Guarantee that we only start reading messages after we have sent
        // the connected event. If no one is consuming events yet, we will
        // suspend until someone does.
        // We should be able to do this in the initializer, as nobody consumes values anyway
        self.readNextMessage()
        do {
            var count = 1
            for try await message in messages {
                let meta = MessageMetadata(number: count)
                await self.events.send(.message(message, metadata: meta))
                count += 1
            }
        } catch {
            logger.error("WebSocketClient event error: \(error)")
            self.events.fail(error)
        }
    }
    
    private func onClose(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async {
        logger.debug("""
        WebSocketClient closed connection with code \(closeCode.rawValue), \
        reason: \(reason.map { String(decoding: $0, as: UTF8.self) } ?? "nil")
        """)
        await self.events.send(.state(.disconnected))
        self.events.finish()
    }
    
    private func didCompleteWithError(_ error: Error?) async {
        guard let error else { return }
        
        let nsError = error as NSError
        let reason = nsError.localizedFailureReason ?? nsError.localizedDescription
        logger.debug("""
            WebSocketClient did complete with error (code: \(nsError.code), reason: \(reason))
            """)
        self.events.fail(nsError)
    }
    
    private func readNextMessage() {
        guard task.closeCode == .invalid else {
            messages.finish()
            return
        }
#if canImport(Darwin)
        task.receive { [weak self] result in
            Task { [weak self] in
                do {
                    let message = try result.get()
                    await self?.messages.send(message)
                    self?.readNextMessage()
                } catch {
                    self?.messages.fail(error)
                }
            }
        }
#endif
    }
}

// MARK: - Helper

final class WebSocketTaskDelegateHandler: NSObject {
    private let logger: Logger
    private let onOpen: (_ `protocol`: String?) -> Void
    private let onClose: (_ closeCode: URLSessionWebSocketTask.CloseCode, _ reason: Data?) -> Void
    private let didCompleteWithError: (_ error: Error?) -> Void
    
    init(
        logger: Logger,
        onOpen: @escaping (_ `protocol`: String?) -> Void,
        onClose: @escaping (_ closeCode: URLSessionWebSocketTask.CloseCode, _ reason: Data?) -> Void,
        didCompleteWithError: @escaping (_ error: Error?) -> Void
    ) {
        self.logger = logger
        self.onOpen = onOpen
        self.onClose = onClose
        self.didCompleteWithError = didCompleteWithError
    }
    
    func didOpenWithProtocol(_ protocol: String?) {
        onOpen(`protocol`)
    }
    
    func didCloseWith(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onClose(closeCode ,reason)
    }
    
    func didCompleteWithError(_ error: Error?) {
        didCompleteWithError(error)
    }
}

extension WebSocketTaskDelegateHandler: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        didOpenWithProtocol(`protocol`)
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        didCloseWith(closeCode: closeCode, reason: reason)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        didCompleteWithError(error)
    }
}
