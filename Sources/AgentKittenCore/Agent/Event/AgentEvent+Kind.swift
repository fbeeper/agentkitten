// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension AgentEvent {
    /// The semantic kind of an ``AgentEvent``.
    public enum Kind: Sendable {
        /// A streaming chunk of text from the model.
        case textDelta(String)
        /// The model started invoking a tool.
        case toolCallStarted(name: String, id: ToolCallID)
        /// The model-requested tool call requires caller approval before it may execute.
        case toolApprovalRequired(call: PendingToolCall)
        /// A tool invocation finished. Check ``ToolCallOutcome`` to distinguish success
        /// from failure.
        case toolCallCompleted(name: String, id: ToolCallID, outcome: ToolCallOutcome)
        /// The turn completed with a final result value.
        case result(Result)
    }
}

extension AgentEvent.Kind: Equatable where Result: Equatable {}
