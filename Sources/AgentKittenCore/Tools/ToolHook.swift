// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Interception points around tool execution.
///
/// Hooks run in declaration order inside ``ToolDefinition``. Pre-execution hooks
/// can transform arguments or cancel execution by throwing. Post-execution hooks
/// can transform or redact the outcome before it is returned to the model.
public protocol ToolHook: Sendable {
    /// Stable name recorded in trace entries for auditability.
    var name: String { get }
    /// The lifecycle phases this hook participates in.
    ///
    /// A hook that declares a phase **must** implement the corresponding method;
    /// the default implementations assert at runtime to catch omissions early.
    var phases: Set<ToolHookPhase> { get }
    /// Called before the tool executes.
    ///
    /// Return a modified call to transform arguments (e.g., PII rehydration).
    /// Throw to cancel execution — results in ``ToolCallOutcome/failure(_:)``.
    func beforeExecute(_ call: PendingToolCall, context: ToolExecutionContext) async throws -> PendingToolCall
    /// Called after the tool executes.
    ///
    /// Return a modified outcome to transform or redact the result before it
    /// is returned to the model (e.g., stripping PII from tool output).
    func afterExecute(
        _ call: PendingToolCall,
        outcome: ToolCallOutcome,
        context: ToolExecutionContext
    ) async -> ToolCallOutcome
}

extension ToolHook {
    public func beforeExecute(
        _ call: PendingToolCall,
        context: ToolExecutionContext
    ) async throws -> PendingToolCall {
        assertionFailure(
            "\(type(of: self)) declares .before in phases but does not implement beforeExecute(_:context:)"
        )
        return call
    }

    public func afterExecute(
        _ call: PendingToolCall,
        outcome: ToolCallOutcome,
        context: ToolExecutionContext
    ) async -> ToolCallOutcome {
        assertionFailure(
            "\(type(of: self)) declares .after in phases but does not implement afterExecute(_:outcome:context:)"
        )
        return outcome
    }
}

// MARK: - ToolHookPhase

/// The lifecycle phase at which a ``ToolHook`` fires.
public enum ToolHookPhase: Sendable, Codable, Equatable, Hashable {
    /// Fires before the tool executes. Can transform arguments or cancel execution.
    case before
    /// Fires after the tool executes. Can transform or redact the outcome.
    case after
}
