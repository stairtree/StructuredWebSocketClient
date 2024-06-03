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
        self.delegateQueue.asUnownedSerialExecutor()
    }
    
    private nonisolated let delegateQueue: OperationQueue

    private let logger: Logger

    private let wsTask: SendableWrappedURLSessionWebSocketTask = .init()
    private var delegateHandler: URLSessionDelegateAdapter<URLSessionWebSocketTransport>?

    /// Will fail if reading a message failed or if the websocket task completes with an error
    private let events: AsyncChannel<WebSocketEvent> = .init()
    private var isAlreadyClosed = false
    
    public init(request: URLRequest, urlSession: URLSession = .shared, logger: Logger? = nil) {
        self.logger = logger ?? .init(label: "URLSessionWebSocketTransport")

        self.delegateQueue = urlSession.delegateQueue
        self.delegateHandler = URLSessionDelegateAdapter() // self is not yet available in non-isolated init
        let urlSession = URLSession(configuration: urlSession.configuration, delegate: self.delegateHandler, delegateQueue: urlSession.delegateQueue)
        self.wsTask.task = urlSession.webSocketTask(with: request)
        self.delegateHandler?.setDelegate(self) // so we have to set the delegate here
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await self.wsTask.send(message)
    }
    
    public nonisolated func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logger.trace("\(#function) called")
        // If the task is already closed, we need to call onClose, as that is
        // the only way the events channel is finished.
        guard self.wsTask.closeCode == .invalid else {
            Task { await self.onClose(closeCode: closeCode, reason: reason, caller: "\(#function) [1]") }
            return
        }
        self.wsTask.cancel(with: closeCode, reason: reason) // sends close frame
        // although if the socket never opened, we still need to close the events… 🤦‍♂️
        Task { await self.onClose(closeCode: closeCode, reason: reason, caller: "\(#function) [2]") }
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
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
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
    
    private func onClose(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?, caller: String = #function) async {
        logger.trace("\(#function) called from \(caller)")
        guard !self.isAlreadyClosed else {
            logger.trace("self.isAlreadyClosed in \(#function) called from \(caller)")
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
    
    private func didCompleteWithError(_ error: (any Error)?, caller: String = #function) async {
        logger.trace("\(#function) with isAlreadyClosed: \(self.isAlreadyClosed), error: \(String(describing: error)) called from \(caller)")
        guard let error, !self.isAlreadyClosed else { return }
        
        let nsError = error as NSError
        let reason = nsError.localizedFailureReason ?? nsError.localizedDescription
        self.logger.debug("""
            WebSocketClient did complete with error (code: \(nsError.code), reason: \(reason))
            """)
        self.logger.trace("WebSocketTask close code: \(self.wsTask.closeCode)")
        await self.events.send(.failure(nsError))
        // If the task is already closed, we need to call onClose, as that is
        // the only way the events channel is finished.
        await self.onClose(closeCode: .abnormalClosure, reason: Data(reason.utf8))
    }
    
    private func readNextMessage(_ number: Int) async {
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
            await self.events.send(.message(message, metadata: meta))
            Task { await self.readNextMessage(number + 1) }
        } catch {
            guard !self.isAlreadyClosed else {
                // When the task finishes normally, we'll get an ENOTCONN error; suppress it.
                return
            }
            self.logger.error("Receive failure: \(String(reflecting: error))")
            await self.events.send(.failure(error))
            await self.onClose(closeCode: .abnormalClosure, reason: Data(error.localizedDescription.utf8))
        }
    }
}

extension URLSessionWebSocketTask.Message {
    package var loggingDescription: String {
        switch self {
        case .data(let data): "data(\(String(reflecting: data)))"
        case .string(let string): "\"\(string)\""
        #if canImport(Darwin)
        @unknown default: "unknown message type"
        #endif
        }
    }
}

/// We need to be able to have not yet initialized the task when setting up the session delegate, especially on
/// Linux; thus we use trivial forwarding wrapper to sidestep the compiler. It also conveniently takes care of
/// the missing Sendable conformance on Linux as well.
private final class SendableWrappedURLSessionWebSocketTask: @unchecked Sendable {
    var task: URLSessionWebSocketTask!
    var closeCode: URLSessionWebSocketTask.CloseCode { self.task.closeCode }
    var state: URLSessionTask.State { self.task.state }

    init() {}

    func resume() { self.task.resume() }
    func send(_ message: URLSessionWebSocketTask.Message) async throws { try await self.task.send(message) }
    func receive() async throws -> URLSessionWebSocketTask.Message { try await self.task.receive() }
    func cancel(with code: URLSessionWebSocketTask.CloseCode, reason: Data?) { self.task.cancel(with: code, reason: reason) }
}
