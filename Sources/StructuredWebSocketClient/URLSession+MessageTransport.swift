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

public final class URLSessionWebSocketTransport: MessageTransport {
    private let logger: Logger
    private let task: URLSessionWebSocketTask
    private var delegateHandler: WebSocketTaskDelegateHandler!
    private var messages: AsyncThrowingChannel<URLSessionWebSocketTask.Message, Error> = .init()
    public let events: AsyncThrowingChannel<WebSocketEvents, Error> = .init()
    
    public init(request: URLRequest, urlSession: URLSession = .shared, logger: Logger? = nil) {
        self.logger = logger ?? .init(label: "URLSessionWebSocketTransport")
        self.task = urlSession.webSocketTask(with: request)
        self.delegateHandler = WebSocketTaskDelegateHandler(
            onOpen: { [weak self, messages, logger = self.logger] `protocol` in
                await self?.events.send(.state(.connected))
                // Guarantee that we only start reading messages after we have sent
                // the connected event. If no one is consuming events yet, we will
                // suspend until someone does.
                // We should be able to do this in the initializer, as nobody consumes values anyway
                self?.readNextMessage()
                do {
                    var count = 1
                    for try await message in messages {
                        let meta = MessageMetadata(number: count, receivedAt: .now())
                        await self?.events.send(.message(message, metadata: meta))
                        count += 1
                    }
                } catch {
                    logger.error("WebSocketClient event error: \(error)")
                    // await events.send(.error(error))
                }
                logger.info("Transport message stream finished")
                // self.events.finish()
            },
            onClose: { [weak self, logger = self.logger] closeCode, reason in
                logger.debug("""
                    WebSocketClient closed connection with code \(closeCode.rawValue), \
                    reason: \(reason.map { String(decoding: $0, as: UTF8.self) } ?? "nil")
                    """)
                await self?.events.send(.state(.disconnected))
                self?.events.finish()
            })
        #if canImport(Darwin)
        self.task.delegate = self.delegateHandler
        #endif
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await task.send(message)
    }
    
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task.cancel(with: closeCode, reason: reason)
    }
    
    public func resume() {
        task.resume()
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
