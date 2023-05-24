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

public final class WebSocketClient {
    public enum State: Equatable, Hashable {
        case disconnecting, disconnected, connecting, connected
    }
    
    private var _state: State = .disconnected {
        didSet {
            guard _state != oldValue else { return }
            stateContinuation.yield(_state)
        }
    }
    
    private var stateContinuation: AsyncStream<State>.Continuation!
    public private(set) var stateStream: AsyncStream<State>!
    
    public let label: String
    private let logger: Logger
    internal let transport: MessageTransport
    private var messageTask: Task<Void, Error>?
    
    public init(
        label: String = "",
        transport: MessageTransport,
        logger: Logger? = nil
    ) {
        self.label = label
        self.transport = transport
        self.logger = logger ?? Logger(label: label)
        self.transport.transportDelegate = self
        self.stateStream = .init(bufferingPolicy: .unbounded) { continuation in
            self.stateContinuation = continuation
        }
    }
    
    deinit {
        self.logger.trace("♻️ Deinit of WebSocketClient")
        transport.cancel(with: .goingAway, reason: nil)
    }
    
    public func connect() {
        _state = .connecting
        transport.resume()
    }
    
    public func disconnect(reason: String?) {
        _state = .disconnecting
        transport.cancel(with: .normalClosure, reason: Data(reason?.utf8 ?? "Closing connection".utf8))
    }
    
    func receiveMessagesWhileConnected() -> Task<Void, Error> {
        Task(priority: .high) {
            do {
                // The messages stream from the transport will finish the stream on close
                for try await message in self.transport.messages {
                    try await self.transport.handle(message)
                }
            } catch {
                logger.error("Error in \(#function): \(error)")
            }
            logger.trace("WebSocketClient stopped receiving messages")
        }
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await transport.send(message)
    }
}

// MARK: - MessageTransportDelegate

extension WebSocketClient: MessageTransportDelegate {
    public func didOpenWithProtocol(_ protocol: String?) {
        _state = .connected
        messageTask?.cancel()
        messageTask = receiveMessagesWhileConnected()
    }
    
    public func didCloseWith(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard _state != .disconnected else {
            logger.warning("WebSocketClient already disconnected"); return
        }
        _state = .disconnected
        logger.trace("""
            WebSocketClient closed connection with code \(closeCode.rawValue), \
            reason: \(reason.map { String(decoding: $0, as: UTF8.self) } ?? "nil")
            """)
    }
}

public enum WebSocketError: Error {
    case unknownMessageFormat
}

extension URLSessionWebSocketTask.Message {
    public func data() throws -> Data {
        switch self {
        case let .data(data):
            return data
        case let .string(text):
            return Data(text.utf8)
        @unknown default:
            throw WebSocketError.unknownMessageFormat
        }
    }
}
