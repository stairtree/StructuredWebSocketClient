//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2022 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Network)
import Foundation
import Logging
import Network
import AsyncAlgorithms

public actor NetworkFrameworkWebSocketTransport: MessageTransport {
    /// Force the actor's methods to run on the URL session's delegate operation queue.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        self.operationQueue.asUnownedSerialExecutor()
    }
    /// The actor's underlying queue
    private nonisolated let operationQueue: OperationQueue
    /// The queue that `NWConnection` will use and is shared with the `delegateQueue`.
    private nonisolated let dispatchQueue: DispatchQueue
    
    private let logger: Logger
    
    private let events: AsyncChannel<WebSocketEvent> = .init()
    let outChannel: AsyncChannel<URLSessionWebSocketTask.Message> = .init()
    
    private let connection: NWConnection
    
    public init(url: String, additionalHeaders: [(name: String, value: String)] = [], subProtocols: [String], logger: Logger) {
        self.operationQueue = .init()
        self.dispatchQueue = .init(label: "NetworkFrameworkWebSocketTransport")
        self.operationQueue.underlyingQueue = self.dispatchQueue
        
        var wsLogger = logger
        wsLogger.logLevel = .trace
        self.logger = wsLogger
        
        let endpoint = NWEndpoint.url(URL(string: url)!)
        
        let websocketOptions = NWProtocolWebSocket.Options()
        websocketOptions.setAdditionalHeaders(additionalHeaders)
        websocketOptions.autoReplyPing = true
        websocketOptions.setSubprotocols(subProtocols)
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableFastOpen = true
        tcpOptions.connectionDropTime = 2
        tcpOptions.connectionTimeout = 5
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveCount = 5
        tcpOptions.keepaliveIdle = 2
        tcpOptions.keepaliveInterval = 1
//        tcpOptions.persistTimeout = 2
        
        let parameters = NWParameters(tls: .init(), tcp: tcpOptions)
        parameters.serviceClass = .signaling
        parameters.multipathServiceType = .disabled
        
        parameters.defaultProtocolStack.applicationProtocols.insert(websocketOptions, at: 0)
        
        connection = NWConnection(to: endpoint, using: parameters)
    }
    
    public nonisolated func connect() -> AsyncAlgorithms.AsyncChannel<StructuredWebSocketClient.WebSocketEvent> {
        connection.stateUpdateHandler = { newState in
            self.logger.debug("State changed: \(newState)")
            switch newState {
            case .setup: ()
            case let .waiting(error):
                self.connection.cancel()
            case .preparing: ()
            case .ready: ()
                self.syncAndBlock {
                    self.logger.trace("Awaiting sending connected state")
                    await self.events.send(.state(.connected))
                    self.logger.trace("Sent connected state")
                }
            case let .failed(error):
                self.syncAndBlock {
                    self.logger.trace("Awaiting sending failure state")
                    await self.events.send(.failure(error))
                    self.logger.trace("Sent failure state")
                }
                self.events.finish()
            case .cancelled:
                self.syncAndBlock {
                    self.logger.trace("Awaiting sending disconnected state")
                    await self.events.send(.state(.disconnected(closeCode: .normalClosure, reason: Data("cancelled".utf8))))
                    self.logger.trace("Sent disconnected state")
                }
                self.events.finish()
            @unknown default:
                self.syncAndBlock {
                    self.logger.trace("Awaiting sending disconnected state")
                    await self.events.send(.state(.disconnected(closeCode: .invalid, reason: Data("@unknown default".utf8))))
                    self.logger.trace("Sent disconnected state")
                }
                self.events.finish()
            }
        }
        
        connection.viabilityUpdateHandler = { isViable in
            self.logger.debug("Viability changed: isViable=\(isViable)")
        }
        
        connection.betterPathUpdateHandler = { isAvailable in
            self.logger.debug("Better path available: isAvailable=\(isAvailable)")
        }
        
        receiveMessage(1)
        logger.debug("Starting connection")
        connection.start(queue: self.dispatchQueue)
        logger.debug("Starting to receive")
        return events
    }
    
    /// Send a message
    ///
    /// -Throws `NWError`
    public nonisolated func send(_ message: URLSessionWebSocketTask.Message) async throws {
        guard let data = try? message.data() else {
            logger.error("Unknown message format: \(message)")
            return
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, _>) in
            let metadata = NWProtocolWebSocket.Metadata(opcode: message.nwOpcode)
            let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
            connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    continuation.resume(with: .init { try error.map { throw $0 } })
                }
            )
        }
    }
    
    public nonisolated func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = (try? .init(rawValue: UInt16(closeCode.rawValue))) ?? .protocolCode(.abnormalClosure)
        let context = NWConnection.ContentContext(identifier: "Final Message", metadata: [metadata])
        connection.send(
            content: nil,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    self.logger.error("Error closing websocket: \(error)")
                }
                self.connection.cancel()
                self.events.finish()
            }
        )
    }
    
    private nonisolated func receiveMessage(_ number: Int) {
        connection.receiveMessage { content, context, isComplete, error in
            assert(isComplete || error != nil) // receiveMessage always delivers complete messages
            //self.logger.trace("Received message \(number)")
            if let error {
                self.logger.error("Received error in message receiver: \(error)")
                return
            }
            
            guard let context else {
                self.logger.error("We always expect a context")
                assertionFailure("We always expect a context")
                return
            }
            
            guard !context.isFinal else {
                self.logger.debug("Received final message")
                return
            }
            
            // in case this isn't the final message we expect the websocket protocol
            guard let metadata = context.protocolMetadata(
                definition: NWProtocolWebSocket.definition
            ) as? NWProtocolWebSocket.Metadata
            else {
                self.logger.error("Did not receive WebSocket protocol metadata")
                assertionFailure("Did not receive WebSocket protocol metadata")
                return
            }
            // We will not be sent anything other than .text and .binary
            switch metadata.opcode {
            case .cont:
                self.logger.trace("Received OPCODE: cont")
                assertionFailure("Received OPCODE: cont")
            case .text:
                //self.logger.trace("Received OPCODE: text")
                guard let content else {
                    self.logger.error("Received text message without content")
                    self.receiveMessage(number + 1) // should we even?
                    return
                }
                self.notifyReceived(text: String(decoding: content, as: UTF8.self), number: number)
                
            case .binary:
                //self.logger.trace("Received OPCODE: binary")
                guard let content else {
                    self.logger.error("Received binary message without content")
                    self.receiveMessage(number + 1) // should we even?
                    return
                }
                self.notifyReceived(data: content, number: number)
            case .close:
                self.logger.trace("Received OPCODE: close")
                assertionFailure("Received OPCODE: close")
            case .ping:
                self.logger.trace("Received OPCODE: ping")
                assertionFailure("Received OPCODE: ping")
            case .pong:
                self.logger.trace("Received OPCODE: pong")
                assertionFailure("Received OPCODE: pong")
            @unknown default:
                fatalError()
            }
        }
    }
    
    private nonisolated func notifyReceived(data: Data, number: Int) {
        Task {
            let meta = MessageMetadata(number: number)
            await self.events.send(.message(.data(data), metadata: meta))
            self.receiveMessage(number + 1)
        }
    }
    
    private nonisolated func notifyReceived(text: String, number: Int) {
        Task {
            let meta = MessageMetadata(number: number)
            await self.events.send(.message(.string(text), metadata: meta))
            self.receiveMessage(number + 1)
        }
    }
    
    private nonisolated func syncAndBlock(_ block: sending @escaping () async -> Void) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
                await block()
        }
        semaphore.wait()
    }
}

extension URLSessionWebSocketTask.Message {
    var nwOpcode: NWProtocolWebSocket.Opcode {
        switch self {
        case .data(_): .binary
        case .string(_): .text
        @unknown default:
            fatalError()
        }
    }
}
#endif
