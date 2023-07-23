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
        let tt = TestMessageTransport()
        print("Creating client")
        let client = WebSocketClient(
            label: "Test",
            middleware: NoOpMiddleWare(),
            transport: tt,
            logger: Logger(label: "Test")
        )
        print("Awaiting group")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                print("connecting")
                await client.connect()
            }
            group.addTask {
                print("pushing message")
                await tt.push(.message(.string("Hoy")))
                try await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
                tt.cancel(with: .goingAway, reason: nil)
            }
            group.addTask {
                for await event in client.events {
                    print(event)
                }
                print("Events are done")
            }
            try await group.next()
        }
        print("Done")
    }
}
