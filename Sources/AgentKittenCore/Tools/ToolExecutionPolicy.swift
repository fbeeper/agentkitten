// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Resolves whether a pending tool call may execute.
public protocol ToolExecutionPolicy: Sendable {
    /// Returns the decision for a pending tool call and its turn-scoped policy context.
    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision
}

/// The result of consulting a ``ToolExecutionPolicy`` for one tool call.
public enum ToolExecutionDecision: Sendable, Equatable {
    /// Execute the tool normally.
    case execute
    /// Do not execute the tool and surface the denial to the model.
    case deny(reason: String)
    /// Suspend the active turn until the caller explicitly approves or denies the tool call.
    case requiresApproval
}

/// A policy that always allows tool execution.
public struct AutoApprovePolicy: ToolExecutionPolicy {
    /// Creates an auto-approving policy.
    public init() {}

    /// Always returns ``ToolExecutionDecision/execute``.
    public func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .execute
    }
}

/// Type-erased wrapper around any ``ToolExecutionPolicy``.
public struct AnyToolExecutionPolicy: ToolExecutionPolicy, Sendable {
    private let resolveClosure: @Sendable (PendingToolCall, ToolExecutionContext) async -> ToolExecutionDecision

    /// Wraps a concrete policy for storage.
    public init<P: ToolExecutionPolicy>(_ policy: P) {
        resolveClosure = { call, context in
            await policy.resolve(call: call, context: context)
        }
    }

    /// Resolves the policy decision for a pending tool call.
    public func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        await resolveClosure(call, context)
    }
}
