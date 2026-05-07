// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

// MARK: - Top-level trace snapshot types

/// AgentTrace-owned snapshot of a ``ToolHookPhase`` value.
public enum ToolHookPhaseSnapshot: String, Sendable, Codable, Equatable, Hashable {
    /// Fires before the tool executes.
    case before
    /// Fires after the tool executes.
    case after
}

// MARK: - AgentTrace entry types

/// Metadata recorded in the trace when a ``ToolHook`` fires during tool execution.
public struct ToolHookInvocationInfo: Sendable, Codable, Equatable, Hashable {
    /// The ID of the tool call this hook intercepted.
    public let callID: ToolCallID
    /// The name of the tool being invoked.
    public let toolName: String
    /// The hook's declared name.
    public let hookName: String
    /// Which phase this invocation corresponds to.
    public let phase: ToolHookPhaseSnapshot
    /// Whether the hook modified the call or outcome for its phase.
    public let transformed: Bool

    /// Creates a hook invocation record.
    public init(
        callID: ToolCallID,
        toolName: String,
        hookName: String,
        phase: ToolHookPhaseSnapshot,
        transformed: Bool
    ) {
        self.callID = callID
        self.toolName = toolName
        self.hookName = hookName
        self.phase = phase
        self.transformed = transformed
    }
}

// MARK: - Framework type → snapshot conversions

extension ToolHookPhase {
    var traceSnapshot: ToolHookPhaseSnapshot {
        switch self {
        case .before:
            .before
        case .after:
            .after
        }
    }
}
