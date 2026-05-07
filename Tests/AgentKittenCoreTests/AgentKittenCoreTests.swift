// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore

@Test func coreVersionExists() {
    #expect(!AgentKittenCore.version.isEmpty)
}
