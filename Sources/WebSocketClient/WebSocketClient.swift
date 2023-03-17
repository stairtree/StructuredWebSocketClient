//===----------------------------------------------------------------------===//
//
// This source file is part of the CodableWebSocket open source project
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
@_exported import CodableMessage

public protocol WebSocketClientDelegate: AnyObject {
    func webSocketClient<M>(didChangeState newState: WebSocketClient<M>.State) where M : MessageType
}

public final class WebSocketClient<Message: MessageType> {
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
    private let messageEncoder: JSONEncoder
    private let messageDecoder: JSONDecoder
    private var messageTask: Task<Void, Error>?
    
    internal let messageRegister: MessageRegister = .init()
    
    public init(
        label: String = "",
        transport: MessageTransport,
        messageEncoder: JSONEncoder = .init(),
        messageDecoder: JSONDecoder = .init()
    ) {
        self.label = label
        self.transport = transport
        self.messageEncoder = messageEncoder
        self.messageDecoder = messageDecoder
        transport.transportDelegate = self
        messageDecoder.userInfo[.messageRegister] = self.messageRegister
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
                    try await self.transport.handle(received)
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
    
    /// sends as string
    public func send<M>(_ message: M) async throws where M: Encodable {
        let data = try messageEncoder.encode(message)
        let str = String(decoding: data, as: UTF8.self)
        try await transport.send(.string(str))
    }
    
    // Default handling for JSON messages. Other transports can elect to call this
    public func parse(_ received: URLSessionWebSocketTask.Message) throws -> Message {
        let message: Message
        switch received {
        case let .data(data):
            message = try self.messageDecoder.decode(Message.self, from: data)
        case let .string(text):
            message = try self.messageDecoder.decode(Message.self, from: Data(text.utf8))
        @unknown default:
            throw WebSocketError.unknownMessageFormat
        }
        return message
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

extension WebSocketClient {
    public func unregister(_ name: MessageName) {
        messageRegister.unregister(name)
    }
    
    public func unregisterAll() {
        messageRegister.unregisterAll()
    }
    
    public func register(_ name: MessageName) {
        messageRegister.register(name)
    }
    
    public func name(for value: String) -> MessageName? {
        messageRegister.name(for: value)
    }
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
