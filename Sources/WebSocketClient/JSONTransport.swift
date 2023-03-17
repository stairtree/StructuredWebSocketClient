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

public final class JSONTransport<Message: MessageType>: MessageTransport {
    private let messageEncoder: JSONEncoder
    private let messageDecoder: JSONDecoder
    internal let messageRegister: MessageRegister = .init()
    
    public enum Handling {
        case handled, unhandled(URLSessionWebSocketTask.Message)
    }
    
    let base: MessageTransport
//    let handle: (_ message: URLSessionWebSocketTask.Message, _ base: MessageTransport) async throws -> Handling
    
    public init(
        base: MessageTransport,
//        handle: @escaping (_ message: URLSessionWebSocketTask.Message, _ base: MessageTransport) async throws -> Handling,
        messageEncoder: JSONEncoder = .init(),
        messageDecoder: JSONDecoder = .init()
    ) {
        self.base = base
//        self.handle = handle
        self.messageEncoder = messageEncoder
        self.messageDecoder = messageDecoder
        messageDecoder.userInfo[.messageRegister] = self.messageRegister
    }
    
    public var transportDelegate: MessageTransportDelegate? {
        get { base.transportDelegate }
        set { base.transportDelegate = newValue }
    }
    
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        try await base.receive()
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) async throws {
        // call the handler of the registered message
        try self.parse(received).handle()
    }
    
    /// sends as string
    public func send<M>(_ message: M) async throws where M: Encodable {
        let data = try messageEncoder.encode(message)
        let str = String(decoding: data, as: UTF8.self)
        try await self.send(.string(str))
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await base.send(message)
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
    
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        base.cancel(with: closeCode, reason: reason)
    }
    
    public func resume() {
        base.resume()
    }
}

extension JSONTransport {
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
