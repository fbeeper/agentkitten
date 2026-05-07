// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension ConversationEvent {
    enum Kind: Sendable {
        case textDelta(String)
        case toolCallStarted(name: String, id: ToolCallID, argumentsJSON: String)
        case toolApprovalRequired(call: PendingToolCall)
        case toolCallCompleted(name: String, id: ToolCallID, outcome: ToolCallOutcome)
        case toolHookFired(ToolHookInvocationInfo)
        case result(Result)
    }
}

extension ConversationEvent.Kind: Equatable where Result: Equatable {}
