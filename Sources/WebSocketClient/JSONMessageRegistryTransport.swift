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

/// A `MessageTransport` that will try to decode incoming messages based on previously registered
/// `MessageType`s and call their handler when they arrive.
public final class JSONMessageRegistryTransport<Message: MessageType>: MessageTransport {
    private let messageEncoder: JSONEncoder
    private let messageDecoder: JSONDecoder
    internal let messageRegister: MessageRegister = .init()
    
    let base: MessageTransport
    
    public init(
        base: MessageTransport,
        messageEncoder: JSONEncoder = .init(),
        messageDecoder: JSONDecoder = .init()
    ) {
        self.base = base
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
    
    public func handle(_ received: URLSessionWebSocketTask.Message) throws {
        do {
            // call the handler of the registered message
            try self.parse(received).handle()
            // forward to base
            try base.handle(received)
        } catch {
            try base.handle(received)
        }
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

extension JSONMessageRegistryTransport {
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

public protocol MessageType: Decodable {
    func handle()
}

// MARK: MessageName

/// A type-eraser for incoming messages
///
/// The name encapsulates all information of how to decode and handle a message.
/// Outgoing messages are just plain `Encodable`s.
/// - Note: All names used by a client must be registered with a registry before receiving them. The
///         registry must be passed into the top level decoder.
public struct MessageName: Codable, Equatable, Hashable {
    
    /// Type erased closure to decode the request
    public let decoder: (Decoder, SingleValueDecodingContainer) throws -> Any
    
    /// Type-erased handler for the message
    public let handler: (Any) -> Void
    
    /// The internal `String` representation of this `MessageName`
    ///
    /// This is used as the discriminator when decoding
    public let value: String
    
    public init<M>(
        _ value: String,
        associatedType: M.Type,
        handler: @escaping (M) -> Void
    ) where M: Decodable {
        self.value = value
        self.decoder = { _, container in try container.decode(M.self) }
        self.handler = { message in handler(message as! M) }
    }
    
    /// Builder for inbound message names
    public static func initializer<M>(
        for value: String,
        ofType type: M.Type
    ) -> (@escaping (M) -> Void) -> MessageName where M: Decodable {
        return { handler in
            return .init(value, associatedType: type, handler: handler)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let registry = decoder.userInfo[.messageRegister] as? MessageRegister else {
            fatalError("No MessageRegister found in decoder's userInfo")
        }
        guard let name = registry.name(for: value) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "No registered Name for id `\(value)`",
                underlyingError: MessageError.unregisteredMessageName(value)
            ))
        }
        
        self = name
    }
    
    public static func == (lhs: MessageName, rhs: MessageName) -> Bool {
        return lhs.value == rhs.value
    }
            
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.value)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }
}

public enum MessageError: Error, Hashable {
    case unregisteredMessageName(String)
}

// MARK: ChildHandler

/// Type-erased handler for messages
///
/// Use to defer declaring the message type and leave it to a higher level library
public protocol ChildHandler {
    func handle(_ message: Any)
    func decode(_ decoder: Decoder) throws -> Any
}

extension MessageName {
    public init<M>(name: String, childHandler: M) where M: ChildHandler {
        self.value = name
        self.handler = { message in childHandler.handle(message) }
        self.decoder = { decoder, _ in try childHandler.decode(decoder) }
    }
}

// MARK: MessageRegister

extension CodingUserInfoKey {
    public static let messageRegister: CodingUserInfoKey = .init(rawValue: "messageRegister")!
}

public final class MessageRegister {
    /// Registry for known inbound message names
    private var names: [String: MessageName] = [:]
    /// Lock protecting the message name register
    private let lock: NSLock = .init()
    /// - Warning: For testing only
    internal var registeredNames: AnyCollection<MessageName> { .init(names.values) }
    
    public init() {}
    
    public func unregister(_ name: MessageName) {
        lock.lock()
        if self.names[name.value] != nil {
            self.names[name.value] = nil
        }
        lock.unlock()
    }
    
    public func unregisterAll() {
        lock.lock()
        self.names = [:]
        lock.unlock()
    }
    
    public func register(_ name: MessageName) {
        lock.lock()
        if self.names[name.value] == nil {
            self.names[name.value] = name
        }
        lock.unlock()
    }
    
    public func name(for value: String) -> MessageName? {
        let name: MessageName?
        lock.lock()
        name = self.names[value]
        lock.unlock()
        return name
    }
}
