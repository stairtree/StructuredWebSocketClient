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
import Logging

/// Assumes messages containing JSON and logs them
public final class JSONLoggingTransport: MessageTransport {
    private let logger: Logger
    let label: String
    let base: MessageTransport
    
    public init(label: String, base: MessageTransport, logger: Logger? = nil) {
        self.label = label
        self.base = base
        self.logger = logger ?? Logger(label: label)
    }
    
    public var transportDelegate: MessageTransportDelegate? {
        get { base.transportDelegate }
        set { base.transportDelegate = newValue }
    }
    
    public var messages: WebSocketStream { base.messages }
    
    public func handle(_ received: URLSessionWebSocketTask.Message) async throws {
        let json = try JSONSerialization.jsonObject(with: try received.data())
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        logger.debug("⬇︎: \(String(decoding: data, as: UTF8.self))")
        try await base.handle(received)
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        let json = try JSONSerialization.jsonObject(with: try message.data())
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        logger.debug("⬆︎: \(String(decoding: data, as: UTF8.self))")
        try await base.send(message)
    }
    
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        base.cancel(with: closeCode, reason: reason)
    }
    
    public func resume() {
        base.resume()
    }
}
