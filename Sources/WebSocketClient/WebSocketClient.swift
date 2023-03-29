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

public protocol WebSocketClientDelegate: AnyObject {
    func webSocketClient(didChangeState newState: WebSocketClient.State)
}

public final class WebSocketClient {
    public enum State: Equatable, Hashable {
        case disconnecting, disconnected, connecting, connected
    }
    
    public var state: State = .disconnected {
        didSet {
            guard state != oldValue else { return }
            delegate?.webSocketClient(didChangeState: state)
        }
    }
    public weak var delegate: WebSocketClientDelegate?
    
    public let label: String
    internal let transport: MessageTransport
    private var messageTask: Task<Void, Error>?
    
    public init(
        label: String = "",
        transport: MessageTransport
    ) {
        self.label = label
        self.transport = transport
        self.transport.transportDelegate = self
    }
    
    deinit {
        transport.cancel(with: .goingAway, reason: nil)
    }
    
    public func connect() {
        state = .connecting
        transport.resume()
    }
    
    public func disconnect() {
        state = .disconnecting
        transport.cancel(with: .normalClosure, reason: Data("Closing connection".utf8))
    }
    
    func receiveMessagesWhileConnected() -> Task<Void, Error> {
        Task(priority: .high) {
            while !Task.isCancelled && self.state == .connected {
                do {
                    let received = try await self.transport.receive()
                    // If a transport handles the message it will return `nil`.
                    // The transport MUST call the message's `.handle(_:)` method then.
                    try self.transport.handle(received)
                } catch {
                    print("\(error)")
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
        state = .connected
        messageTask?.cancel()
        messageTask = receiveMessagesWhileConnected()
    }
    
    public func didCloseWith(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        state = .disconnected
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