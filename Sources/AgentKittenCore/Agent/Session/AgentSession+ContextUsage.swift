// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension AgentSession {
    /// Returns the current provider context usage immediately when the session is idle.
    ///
    /// The usage estimate comes from the active provider conversation.
    ///
    /// - Throws: ``AgentSessionError/noActiveConversation`` if the session has not
    ///   created a provider conversation yet.
    public func contextUsage() async throws -> ContextUsage {
        let lease = try operationGate.begin(InferenceSessionOperationKind.contextUsage)
        defer {
            lease.end()
        }
        return try await conversationProvider.contextUsage()
    }
}
