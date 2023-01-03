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
