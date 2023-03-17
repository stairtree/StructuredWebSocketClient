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

/// Type-erased handler for messages
///
/// Use to defer declaring the message type and leave it to a higher level library
public protocol ChildHandler {
    func handle(_ message: Any)
    func decode(_ decoder: Decoder) throws -> Any
}

extension MessageName {
    public init<M>(name: String, childHandler: M) where M: ChildHandler {
        self.value = name
        self.handler = { message in childHandler.handle(message) }
        self.decoder = { decoder, _ in try childHandler.decode(decoder) }
    }
}
