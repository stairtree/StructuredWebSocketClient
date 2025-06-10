extension CodingUserInfoKey {
    public static let jsonMessageRegistry = CodingUserInfoKey(rawValue: "jsonMessageRegistry")!
}

public final class JSONMessageRegistry: @unchecked Sendable {
    /// Registry for known inbound message names
    private var names: [String: JSONMessageName] = [:]
    /// Lock protecting the message name register
    private let lock: NIOLock = .init()
    
    public init() {}
    
    public func unregister(_ name: JSONMessageName) {
        self.lock.withLock {
            _ = self.names.removeValue(forKey: name.value)
        }
    }
    
    public func unregisterAll() {
        self.lock.withLock {
            self.names.removeAll()
        }
    }
    
    public func register(_ name: JSONMessageName) {
        self.lock.withLock {
            assert(self.names[name.value] == nil, "Attempted to register duplicate message name \(name.value)")
            
            if self.names[name.value] == nil {
                self.names[name.value] = name
            }
        }
    }
    
    public func name(for value: String) -> JSONMessageName? {
        self.lock.withLock {
            self.names[value]
        }
    }
}
