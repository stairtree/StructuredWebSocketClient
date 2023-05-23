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
        transport.cancel(with: .goingAway, reason: nil)
    }
    
    public func connect() {
        _state = .connecting
        transport.resume()
    }
    
    public func disconnect() {
        _state = .disconnecting
        transport.cancel(with: .normalClosure, reason: Data("Closing connection".utf8))
    }
    
    func receiveMessagesWhileConnected() -> Task<Void, Error> {
        Task(priority: .high) {
            while !Task.isCancelled && self._state == .connected {
                do {
                    let received = try await self.transport.receive()
                    try await self.transport.handle(received)
                } catch {
                    logger.error("\(error)")
                    // FIXME: This should check for the error.
                    //        Also, disconnecting might already cancel the task,
                    //        but not necessarily, as a disconnected socket will
                    //        not send state changes anymore.
                }
            }
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
        _state = .disconnected
        messageTask?.cancel()
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
