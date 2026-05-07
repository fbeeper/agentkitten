// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Errors raised by ``AgentSession`` operations.
public enum AgentSessionError: Error, Sendable, Equatable {
    /// Another session operation is already mutating conversation state.
    case concurrentOperationInProgress(active: InferenceSessionOperationKind)

    /// The session has no active provider conversation.
    case noActiveConversation
}
