// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Input passed to a validator for one assistant response.
public struct ValidationContext<Result: Sendable>: Sendable {
    /// The result being validated.
    public let result: Result
    /// The originating user message for the enclosing turn.
    public let userMessage: UserMessage
    /// The enclosing turn invocation identifier.
    public let invocationID: InvocationID
    /// Session-scoped scratchpad storage available during validation.
    public let sessionState: AgentSession.SessionStateAccess
}
