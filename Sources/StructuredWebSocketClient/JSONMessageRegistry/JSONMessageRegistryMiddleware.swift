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
public final class JSONMessageRegistryMiddleware<Message: JSONMessageType>: WebSocketMessageInboundMiddleware {
    private let messageDecoder: JSONDecoder
    internal let messageRegistry: JSONMessageRegistry = .init()
    
    public let nextIn: (any WebSocketMessageInboundMiddleware)?
    
    public init(
        nextIn: (any WebSocketMessageInboundMiddleware)?,
        messageDecoder: JSONDecoder = .init()
    ) {
        self.nextIn = nextIn
        self.messageDecoder = messageDecoder
        messageDecoder.userInfo[.jsonMessageRegistry] = self.messageRegistry
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message, metadata: MessageMetadata) async throws -> MessageHandling {
        do {
            // call the handler of the registered message
            try await self.parse(received).handle()
            return .handled
        } catch {
            return try await self.nextIn?.handle(received, metadata: metadata) ?? .unhandled(received)
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

extension JSONMessageRegistryMiddleware {
    public func unregister(_ name: JSONMessageName) {
        self.messageRegistry.unregister(name)
    }
    
    public func unregisterAll() {
        self.messageRegistry.unregisterAll()
    }
    
    public func register(_ name: JSONMessageName) {
        self.messageRegistry.register(name)
    }
    
    public func name(for value: String) -> JSONMessageName? {
        self.messageRegistry.name(for: value)
    }
}

/// A message recieved by a ``JSONMessageRegistryMiddleware``.
public protocol JSONMessageType: Sendable, Decodable {
    /// Called when the middleware receives a message of the appropriate type.
    func handle() async
}
