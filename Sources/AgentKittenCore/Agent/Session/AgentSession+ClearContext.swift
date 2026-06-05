// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension AgentSession {
    /// Controls whether ``clearContext(state:)`` also clears session state.
    public enum StateClearPolicy: Sendable {
        /// Clear the provider context and session-state scratchpad.
        case clear
        /// Clear only the provider context.
        case preserve
    }

    /// Discards the active provider conversation immediately when the session is idle,
    /// optionally clearing session state.
    ///
    /// The session itself - behavior, tools, provider configuration, and
    /// AgentKitten ``trace`` - is preserved. Provider-side conversation
    /// history is always cleared; session state is controlled by `state`.
    ///
    /// Awaiting this method guarantees the next turn starts fresh:
    ///
    /// ```swift
    /// try await session.clearContext()
    /// let turn = try await session.send("Summarize: \(paragraph)")
    /// ```
    ///
    /// - Parameter statePolicy: Whether to clear session state. Defaults to `.clear`.
    public func clearContext(state statePolicy: StateClearPolicy = .clear) async throws {
        let lease = try operationGate.begin(InferenceSessionOperationKind.clearContext)
        defer {
            lease.end()
        }
        try await performClearContext(state: statePolicy)
    }

    private func performClearContext(state statePolicy: StateClearPolicy) async throws {
        switch statePolicy {
        case .clear:
            switch state {
            case .disabled:
                break
            case .readOnly:
                throw SessionStateError.readOnlyMutation
            case .enabled(let state):
                try await state.clear()
            }
        case .preserve:
            break
        }
        conversationProvider.clearActiveConversation()
    }
}
