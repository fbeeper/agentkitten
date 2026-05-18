// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Test func coreVersionExists() {
    #expect(!AgentKittenCore.version.isEmpty)
}
