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
import AsyncAlgorithms
#if canImport(FoundationNetworking)
@preconcurrency import FoundationNetworking
#endif

/// On Linux, we need to fake a Sendable conformance for OperationQueue.
#if !canImport(Darwin)
#if $RetroactiveAttribute
extension OperationQueue: @unchecked @retroactive Sendable {}
#else
extension OperationQueue: @unchecked Sendable {}
#endif
#endif

/// Mark the SerialExecutor conformance retroactive on all platforms.
#if $RetroactiveAttribute
extension OperationQueue: @retroactive SerialExecutor {}
#else
extension OperationQueue: SerialExecutor {}
#endif

extension OperationQueue {
    #if canImport(Darwin)
    public func enqueue(_ job: UnownedJob) {
        self.addOperation { job.runSynchronously(on: self.asUnownedSerialExecutor()) }
    }
    #else
    public func enqueue(_ job: consuming ExecutorJob) {
        let unconsumingJob = UnownedJob(job)
        self.addOperation { unconsumingJob.runSynchronously(on: self.asUnownedSerialExecutor()) }
    }
    #endif
    
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        .init(ordinary: self)
    }
    
    public func isSameExclusiveExecutionContext(other: OperationQueue) -> Bool {
        self.isEqual(other)
    }
}


public actor URLSessionWebSocketTransport: MessageTransport, SimpleURLSessionTaskDelegate {
    /// Force the actor's methods to run on the URL session's delegate operation queue.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        self.session.delegateQueue.asUnownedSerialExecutor()
    }
    
    private nonisolated let session: URLSession
    private let logger: Logger
    private let wsTask: URLSessionWebSocketTask
    private var delegateHandler: URLSessionDelegateAdapter<URLSessionWebSocketTransport>?
    private var isAlreadyClosed = false
    /// Will fail if reading a message failed or if the websocket task completes with an error
    private let events: AsyncChannel<WebSocketEvent> = .init()
    
    public init(request: URLRequest, urlSession: URLSession = .shared, logger: Logger? = nil) async {
        self.session = urlSession
        self.logger = logger ?? .init(label: "URLSessionWebSocketTransport")
        self.wsTask = urlSession.webSocketTask(with: request)
        self.delegateHandler = .init(adapting: self)
        #if canImport(Darwin)
        self.wsTask.delegate = self.delegateHandler
        #endif
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await self.wsTask.send(message)
    }
    
    public nonisolated func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // If the task is already closed, we need to call onClose, as that is
        // the only way the events channel is finished.
        guard self.wsTask.closeCode == .invalid else {
            Task { await self.onClose(closeCode: closeCode, reason: reason) }
            return
        }
        self.wsTask.cancel(with: closeCode, reason: reason)
    }
    
    public nonisolated func connect() -> AsyncChannel<WebSocketEvent> {
        self.wsTask.resume()
        return self.events
    }
    
    // MARK: - Private
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { await self.onOpen(protocol: `protocol`) }
    }
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { await self.onClose(closeCode: closeCode, reason: reason) }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { await self.didCompleteWithError(error) }
    }
    
    private func onOpen(protocol: String?) async {
        guard !self.isAlreadyClosed else { return }
        
        await self.events.send(.state(.connected))
        // Guarantee that we only start reading messages after we have sent
        // the connected event. If no one is consuming events yet, we will
        // suspend until someone does.
        // We should be able to do this in the initializer, as nobody consumes values anyway
        await self.readNextMessage(1)
    }
    
    private func onClose(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async {
        guard !self.isAlreadyClosed else {
            // Due to delegate callbacks, we can get here more than once. Don't send multiple
            // disconnect events or log multiple closures.
            return
        }
        logger.debug("""
        WebSocketClient closed connection with code \(closeCode.rawValue), \
        reason: \(reason.map { String(decoding: $0, as: UTF8.self) } ?? "nil")
        """)
        await self.events.send(.state(.disconnected(closeCode: closeCode, reason: reason)))
        self.events.finish()
        self.isAlreadyClosed = true
    }
    
    private func didCompleteWithError(_ error: Error?) async {
        guard let error, !self.isAlreadyClosed else { return }
        
        let nsError = error as NSError
        let reason = nsError.localizedFailureReason ?? nsError.localizedDescription
        self.logger.debug("""
            WebSocketClient did complete with error (code: \(nsError.code), reason: \(reason))
            """)
        await self.events.send(.failure(nsError))
        // If the task is already closed, we need to call onClose, as that is
        // the only way the events channel is finished.
        if self.wsTask.closeCode != .invalid {
            await self.onClose(closeCode: .abnormalClosure, reason: Data(reason.utf8))
        }
    }
    
    private func readNextMessage(_ number: Int) async {
#if canImport(Darwin)
        switch self.wsTask.state {
        case .running, .suspended: break
        case .canceling, .completed: return
        #if canImport(Darwin)
        @unknown default: fatalError()
        #endif
        }

        do {
            let message = try await self.wsTask.receive()
            let meta = MessageMetadata(number: number)
            
            self.logger.trace("WebSocketClient did receive message with number \(number) \(String(reflecting: message))")
            await self.events.send(.message(message, metadata: meta))
            Task { await self.readNextMessage(number + 1) }
        } catch {
            guard !self.isAlreadyClosed else {
                // When the task finishes normally, we'll get an ENOTCONN error; suppress it.
                return
            }
            self.logger.error("Receive failure: \(error)")
            await self.events.send(.failure(error))
            await self.onClose(closeCode: .abnormalClosure, reason: Data(error.localizedDescription.utf8))
        }
#endif
    }
}
