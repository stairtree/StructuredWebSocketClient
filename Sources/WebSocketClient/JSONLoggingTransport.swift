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

/// Assumes messages containing JSON and logs them
public final class JSONLoggingTransport: MessageTransport {
    let label: String
    let base: MessageTransport
    
    public init(label: String, base: MessageTransport) {
        self.label = label
        self.base = base
    }
    
    public var transportDelegate: MessageTransportDelegate? {
        get { base.transportDelegate }
        set { base.transportDelegate = newValue }
    }
    
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        try await base.receive()
    }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) throws {
        let json = try JSONSerialization.jsonObject(with: try received.data())
        print("[\(label)] ⬇️:", String(decoding: try JSONSerialization.data(withJSONObject: json, options: []), as: UTF8.self))
        try base.handle(received)
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        let json = try JSONSerialization.jsonObject(with: try message.data())
        print("[\(label)] ⬆️:", String(decoding: try JSONSerialization.data(withJSONObject: json, options: []), as: UTF8.self))
        try await base.send(message)
    }
    
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        base.cancel(with: closeCode, reason: reason)
    }
    
    public func resume() {
        base.resume()
    }
}
