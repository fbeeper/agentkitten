// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Controls which registered tools are exposed to the model for a given turn.
public enum ToolSelection: Sendable, Equatable, Hashable {
    /// All registered tools are available.
    case all
    /// No tools are exposed; the model reasons without tool access.
    case disabled
    /// Only tools with the listed names are exposed.
    case including(Set<String>)
    /// All registered tools except those with the listed names are exposed.
    case excluding(Set<String>)

    /// Returns whether a tool with `toolName` is available under this selection.
    public func allows(toolName: String) -> Bool {
        switch self {
        case .all:
            true
        case .disabled:
            false
        case .including(let names):
            names.contains(toolName)
        case .excluding(let names):
            !names.contains(toolName)
        }
    }
}
