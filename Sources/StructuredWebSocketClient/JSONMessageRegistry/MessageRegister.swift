import class Foundation.NSLock

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

#if !canImport(Darwin)
extension NSLock {
    fileprivate func withLock<R>(_ closure: () throws -> R) rethrows -> R {
        self.lock()
        defer { self.unlock() }
        return try closure()
    }
}
#endif
