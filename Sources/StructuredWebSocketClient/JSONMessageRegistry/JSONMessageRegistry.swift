import AsyncHelpers

extension CodingUserInfoKey {
    public static let jsonMessageRegistry = CodingUserInfoKey(rawValue: "jsonMessageRegistry")!
}

public final class JSONMessageRegistry: @unchecked Sendable {
    /// Registry for known inbound message names
    private var names: [String: MessageName] = [:]
    /// Lock protecting the message name register
    private let lock: Locking.FastLock = .init()
    
    public init() {}
    
    public func unregister(_ name: MessageName) {
        self.lock.withLock {
            _ = self.names.removeValue(forKey: name.value)
        }
    }
    
    public func unregisterAll() {
        self.lock.withLock {
            self.names.removeAll()
        }
    }
    
    public func register(_ name: MessageName) {
        self.lock.withLock {
            assert(self.names[name.value] == nil, "Attempted to register duplicate message name \(name.value)")
            
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
