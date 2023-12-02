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

#if !canImport(Darwin)
@preconcurrency
#endif
import Foundation
import AsyncAlgorithms
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A `MessageTransport` that will try to decode incoming messages based on previously registered
/// `MessageType`s and call their handler when they arrive.
public final class JSONMessageRegistryTransport<Message: MessageType>: WebSocketMessageInboundMiddleware {
    private let messageDecoder: JSONDecoder
    internal let messageRegister: MessageRegister = .init()
    
    public let nextIn: WebSocketMessageInboundMiddleware?
    
    public init(
        nextIn: WebSocketMessageInboundMiddleware?,
        messageDecoder: JSONDecoder = .init()
    ) {
        self.nextIn = nextIn
        self.messageDecoder = messageDecoder
        messageDecoder.userInfo[.messageRegister] = self.messageRegister
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message, metadata: MessageMetadata) async throws -> MessageHandling {
        do {
            // call the handler of the registered message
            try await self.parse(received).handle()
            return .handled
        } catch {
            if let nextIn { return try await nextIn.handle(received, metadata: metadata) }
            return .unhandled(received)
        }
    }
    
    // Default handling for JSON messages.
    private func parse(_ received: URLSessionWebSocketTask.Message) throws -> Message {
        let message: Message
        switch received {
        case let .data(data):
            message = try self.messageDecoder.decode(Message.self, from: data)
        case let .string(text):
            message = try self.messageDecoder.decode(Message.self, from: Data(text.utf8))
        #if canImport(Darwin)
        @unknown default:
            throw WebSocketError.unknownMessageFormat
        #endif
        }
        return message
    }
}

extension JSONMessageRegistryTransport {
    public func unregister(_ name: MessageName) {
        self.messageRegister.unregister(name)
    }
    
    public func unregisterAll() {
        self.messageRegister.unregisterAll()
    }
    
    public func register(_ name: MessageName) {
        self.messageRegister.register(name)
    }
    
    public func name(for value: String) -> MessageName? {
        self.messageRegister.name(for: value)
    }
}

public protocol MessageType: Decodable {
    func handle() async
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
    public let handler: (Any) async -> Void
    
    /// The internal `String` representation of this `MessageName`
    ///
    /// This is used as the discriminator when decoding
    public let value: String
    
    public init<M>(
        _ value: String,
        associatedType: M.Type,
        handler: @escaping (M) async -> Void
    ) where M: Decodable {
        self.value = value
        self.decoder = { _, container in try container.decode(M.self) }
        self.handler = { message in await handler(message as! M) }
    }
    
    /// Builder for inbound message names
    public static func initializer<M>(
        for value: String,
        ofType type: M.Type
    ) -> (@escaping (M) async -> Void) -> MessageName where M: Decodable {
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
    func handle(_ message: Any) async
    func decode(_ decoder: Decoder) throws -> Any
}

extension MessageName {
    public init<M>(name: String, childHandler: M) where M: ChildHandler {
        self.value = name
        self.handler = { message in await childHandler.handle(message) }
        self.decoder = { decoder, _ in try childHandler.decode(decoder) }
    }
}

// MARK: MessageRegister

extension CodingUserInfoKey {
    public static let messageRegister: CodingUserInfoKey = .init(rawValue: "messageRegister")!
}

public final class MessageRegister: @unchecked Sendable {
    /// Registry for known inbound message names
    private var names: [String: MessageName] = [:]
    /// Lock protecting the message name register
    private let lock: NSLock = .init()
    /// - Warning: For testing only
    internal var registeredNames: AnyCollection<MessageName> { .init(self.names.values) }
    
    public init() {}
    
    public func unregister(_ name: MessageName) {
        self.lock.withLock {
            _ = self.names.removeValue(forKey: name.value)
        }
    }
    
    public func unregisterAll() {
        self.lock.withLock {
            self.names = [:]
        }
    }
    
    public func register(_ name: MessageName) {
        self.lock.withLock {
            if self.names[name.value] == nil {
                self.names[name.value] = name
            }
        }
    }
    
    public func name(for value: String) -> MessageName? {
        self.lock.withLock {
            self.names[value]
        }
    }
}
