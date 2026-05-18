// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension AgentSession {
    /// Updates the automatic context compaction policy for future turns.
    ///
    /// The change is actor-isolated and immediate; it is not serialized through
    /// the turn queue. In-flight turns have already passed their start-of-turn
    /// automatic compaction check, so the new policy applies to later turns.
    public func setAutomaticCompactionPolicy(_ policy: AutomaticCompactionPolicy) {
        automaticCompactionPolicy = policy
    }

    /// Compacts the active provider conversation context immediately when the session is idle.
    ///
    /// The session itself - behavior, tools, session state, and AgentKitten
    /// ``trace`` - is preserved.
    ///
    /// - Parameter options: Compaction options. Defaults to summarization compaction.
    /// - Returns: The compaction result. If there is no active provider conversation,
    ///   the result is ``ContextCompactionResult/skipped(_:)``.
    public func compactContext(
        _ options: ContextCompactionOptions = .init(),
    ) async throws -> ContextCompactionResult {
        let lease = try operationGate.begin(InferenceSessionOperationKind.compactContext)
        defer {
            lease.end()
        }
        return try await performManualContextCompaction(
            options,
            invocationID: InvocationID.generate(),
        )
    }

    private func performManualContextCompaction(
        _ options: ContextCompactionOptions,
        invocationID: InvocationID,
    ) async throws -> ContextCompactionResult {
        let result: ContextCompactionResult
        if let compacted = try await conversationProvider.compactActiveConversation(
            options: options,
        ) {
            result = compacted
        } else {
            result = .skipped(.noActiveConversation)
        }
        record(
            kind: .contextCompaction(conversationProvider.compactionTraceInfo(
                mode: .manual,
                result: result,
            )),
            invocationID: invocationID,
        )
        return result
    }
}
