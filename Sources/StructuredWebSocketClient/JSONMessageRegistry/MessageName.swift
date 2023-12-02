/// A type-eraser for incoming messages
///
/// The name encapsulates all information of how to decode and handle a message.
/// Outgoing messages are just plain `Encodable`s.
/// - Note: All names used by a client must be registered with a registry before receiving them. The
///         registry must be passed into the top level decoder.
public struct MessageName: Codable, Equatable, Hashable {
    
    /// Type erased closure to decode the request
    public let decoder: (any Decoder, any SingleValueDecodingContainer) throws -> Any
    
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
    
    public init(from decoder: any Decoder) throws {
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
    
    public func encode(to encoder: any Encoder) throws {
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
    func decode(from decoder: any Decoder) throws -> Any
}

extension MessageName {
    public init<M>(name: String, childHandler: M) where M: ChildHandler {
        self.value = name
        self.handler = { message in await childHandler.handle(message) }
        self.decoder = { decoder, _ in try childHandler.decode(from: decoder) }
    }
}
