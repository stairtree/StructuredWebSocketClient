/// A type-eraser for incoming messages.
///
/// The name encapsulates all information of how to decode and handle a message.
/// Outgoing messages are just plain `Encodable`s.
/// - Note: All names used by a client must be registered with a registry before receiving them. The
///         registry must be passed into the top level decoder.
public struct JSONMessageName: Sendable, Codable, Equatable, Hashable {
    /// Type erased closure to decode the request
    public let decoder: @Sendable (any Decoder) throws -> any Sendable
    
    /// Type-erased handler for the message
    public let handler: @Sendable (any Sendable) async -> Void
    
    /// The internal `String` representation of this ``JSONMessageName``
    ///
    /// This is used as the discriminator when decoding
    public let value: String
    
    public init<M: Decodable & Sendable>(
        _ value: String,
        associatedType: M.Type,
        typeHandler: @escaping @Sendable (M) async -> Void
    ) {
        self.value = value
        self.decoder = { try M.init(from: $0) }
        self.handler = { await typeHandler($0 as! M) }
    }
    
    /// Builder for inbound message names
    public static func initializer<M: Decodable & Sendable>(
        for value: String,
        ofType: M.Type
    ) -> (@escaping @Sendable (M) async -> Void) -> Self {
        { handler in .init(value, associatedType: M.self, typeHandler: handler) }
    }
    
    public init(from decoder: any Decoder) throws {
        guard let registry = decoder.userInfo[.jsonMessageRegistry] as? JSONMessageRegistry else {
            preconditionFailure("No MessageRegister found in decoder's userInfo")
        }

        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        
        guard let name = registry.name(for: value) else {
            throw DecodingError.valueNotFound(JSONMessageName.self, .init(
                codingPath: container.codingPath,
                debugDescription: "No registered MessageName for id `\(value)`",
                underlyingError: JSONMessageError.unregisteredMessageName(value)
            ))
        }
        
        self = name
    }
    
    public static func == (lhs: JSONMessageName, rhs: JSONMessageName) -> Bool {
        lhs.value == rhs.value
    }
            
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.value)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }
}

public enum JSONMessageError: Error, Hashable {
    case unregisteredMessageName(String)
}

/// Semi-type-erased handler for messages
///
/// Use to defer declaring the message type and leave it to a higher level library
public protocol ChildHandler: Sendable {
    func handle(_ message: any Sendable) async
    func decode(from decoder: any Decoder) throws -> any Sendable
}

extension JSONMessageName {
    public init(name: String, childHandler: some ChildHandler) {
        self.value = name
        self.handler = { await childHandler.handle($0) }
        self.decoder = { try childHandler.decode(from: $0) }
    }
}
