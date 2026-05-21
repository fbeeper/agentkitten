// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten

enum PlaygroundToolEventFormatter {
    static func approvalRequired(_ call: PendingToolCall) -> String {
        approvalRequired(toolName: call.name)
    }

    static func approvalRequired(toolName: String) -> String {
        "[tool:approval] \(toolName)"
    }
}
