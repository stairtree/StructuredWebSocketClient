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

import XCTest
import Logging
import StructuredWebSocketClientTestSupport
import StructuredWebSocketClient
import Foundation
#if canImport(FoundationNetworking) && !canImport(Darwin)
@preconcurrency import FoundationNetworking
#endif

final class WebSocketClientTests: XCTestCase {
    override class func setUp() {
        XCTAssert(isLoggingConfigured)
    }
    
    func testNeverOpening() async throws {
        let logger = Logger(label: "Test")
        logger.debug("Creating client")
        // This is an invalid URL - it's not a websocket endpoint
        let request = URLRequest(url: .init(string: "https://www.apple.com")!)
        let tt = URLSessionWebSocketTransport(request: request, urlSession: .shared, logger: logger)
        let client = WebSocketClient(
            inboundMiddleware: NoOpMiddleWare(),
            outboundMiddleware: NoOpMiddleWare(),
            transport: tt,
            logger: logger
        )
        logger.debug("Connecting")
        
        for try await event in client.connect() {
            logger.debug("\(String(reflecting: event))")
        }
        
        logger.debug("Events are done")
    }
    
    func testOpen() async throws {
        let tt = TestMessageTransport(initialMessages: [
            // it's not guaranteed that there aren't messages put inbetween
            .string("initial 1 \(Date())"), .string("initial 2 \(Date())")
        ])
        let logger = Logger(label: "Test")
        logger.debug("Creating client")
        let client = WebSocketClient(
            inboundMiddleware: NoOpMiddleWare(),
            outboundMiddleware: NoOpMiddleWare(),
            transport: tt,
            logger: logger
        )
        logger.debug("Awaiting group")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                logger.debug("Pushing message 3")
                await tt.push(.message(.string("Hoy \(Date())"), metadata: .init(number: 3)))
                if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
                    try await Task.sleep(for: .seconds(1), clock: SuspendingClock())
                } else {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // NSEC_PER_SEC is harder to get at on Linux (it still has to compile after all)
                }
                logger.debug("Pushing message 4")
                await tt.push(.message(.string("Hoy again \(Date())"), metadata: .init(number: 4)))
                tt.close(with: .goingAway, reason: nil)
            }
            group.addTask {
                logger.debug("Connecting")
                for try await event in client.connect() {
                    logger.debug("\(String(reflecting: event))")
                }
                logger.debug("Events are done")
            }
            try await group.next()
        }
    }
    
    func testEchoServer() async throws {
        let logger = Logger(label: "Test")

        // Postman's echo server
        let request = URLRequest(url: .init(string: "wss://ws.postman-echo.com/raw")!)
        let client = WebSocketClient(inboundMiddleware: nil, outboundMiddleware: nil, transport: URLSessionWebSocketTransport(request: request), logger: logger)
        let outMsg = "Hi there"
        let expectation = XCTestExpectation(description: "message received")
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await client.sendMessage(.string(outMsg))
            }
            group.addTask {
                for try await event in client.connect() {
                    if case let .message(message, metadata) = event {
                        XCTAssertEqual(try message.string(), outMsg)
                        XCTAssertEqual(metadata.number, 1)
                        logger.trace("message \(String(reflecting: metadata)) \(message.loggingDescription)")
                        expectation.fulfill()
                        client.disconnect(reason: "done testing")
                    }
                }
            }
            try await group.next()
        }
        #if canImport(Darwin) || swift(>=5.10)
        await self.fulfillment(of: [expectation], timeout: 5.0)
        #else
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5.0), .completed)
        #endif
    }
}

@available(iOS 15.0, *)
extension MessageMetadata: CustomDebugStringConvertible {
    public var debugDescription: String {
        #if canImport(Darwin)
        "Metadata[number=\(self.number) receivedAt=\(self.receivedAt.formatted(.iso8601))]"
        #else
        "Metadata[number=\(self.number) receivedAt=\(self.receivedAt)]"
        #endif
    }
}

func env(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name]
}

let isLoggingConfigured: Bool = {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = env("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ?? .trace
        return handler
    }
    return true
}()

import AsyncAlgorithms
public final class TestNotOpeningTransport: MessageTransport, Sendable {
    private let _events: AsyncChannel<WebSocketEvent> = .init()
    private let events: AsyncChannel<WebSocketEvent> = .init()
    
    public init() {}
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {}
    
    public func close(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        //
    }
    
    public func connect() -> AsyncChannel<WebSocketEvent> {
        Task { [unowned self] in
            for await event in self._events {
                await self.events.send(event)
            }
            self.events.finish()
        }
        return self.events
    }
}
