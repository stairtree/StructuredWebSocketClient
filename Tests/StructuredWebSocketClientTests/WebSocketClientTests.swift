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

final class WebSocketClientTests: XCTestCase {
    func testOpen() async throws {
        LoggingSystem.bootstrap {
            var handler = StreamLogHandler.standardOutput(label: $0)
            handler.logLevel = .trace
            return handler
        }
        let tt = TestMessageTransport(initialMessages: [
            // it's not guaranteed that there aren't messages put inbetween
            .string("initial 1 \(Date())"), .string("initial 2 \(Date())")
        ])
        print("Creating client")
        let client = WebSocketClient(
            inboundMiddleware: NoOpMiddleWare(),
            outboundMiddleware: NoOpMiddleWare(),
            transport: tt,
            logger: Logger(label: "Test")
        )
        print("Awaiting group")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                print("Pushing message 3")
                await tt.push(.message(.string("Hoy \(Date())"), metadata: .init(number: 3)))
                try await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
                print("Pushing message 4")
                await tt.push(.message(.string("Hoy again \(Date())"), metadata: .init(number: 4)))
                tt.close(with: .goingAway, reason: nil)
            }
            group.addTask {
                print("Connecting")
                for try await event in client.connect() {
                    print(event)
                }
                print("Events are done")
            }
            try await group.next()
        }
    }
}
