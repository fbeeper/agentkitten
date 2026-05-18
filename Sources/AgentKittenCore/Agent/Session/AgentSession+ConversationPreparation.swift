// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension AgentSession {
    /// Returns the direct-execution conversation for this turn configuration.
    func conversation(
        executionEnvironment: ExecutionEnvironment,
        turnOverrides: TurnOverrides,
        invocationID: InvocationID,
    ) async throws -> AnyConversation {
        let effectiveConfiguration = EffectiveExecutionConfiguration(
            environment: executionEnvironment,
        )
        // `ConversationProvider` is a value-type actor property, and
        // `resolveConversation` is `mutating async`. Swift will not allow a
        // mutable borrow of actor-isolated stored state across suspension, so
        // we resolve against a local copy and write the updated provider back
        // afterward.
        var providerCopy = conversationProvider
        let resolvedConversation = try await providerCopy.resolveConversation(
            for: effectiveConfiguration,
            automaticCompactionPolicy: automaticCompactionPolicy,
        )
        conversationProvider = providerCopy
        let conversation = resolvedConversation.conversation
        let identity = await conversation.identity()
        record(
            kind: .executionPreparation(AgentTraceEntry.Kind.ExecutionPreparationInfo(
                verdict: resolvedConversation.resolutionKind.traceSnapshot,
                provider: effectiveConfiguration.provider.traceSnapshot,
                toolSelection: effectiveConfiguration.toolSelection.traceSnapshot,
                toolStepBudget: effectiveConfiguration.toolStepBudget.traceSnapshot,
                inferenceConfiguration: effectiveConfiguration.inferenceConfiguration.traceSnapshot,
                inferenceContext: effectiveConfiguration.inferenceContext.traceSnapshot,
                turnOverrides: turnOverrides.traceSnapshot,
            )),
            invocationID: invocationID,
        )
        record(
            kind: .conversationResolved(AgentTraceEntry.Kind.ConversationResolvedInfo(
                identity: identity.traceSnapshot,
                resolutionKind: resolvedConversation.resolutionKind.traceSnapshot,
            )),
            invocationID: invocationID,
        )
        await recordAutomaticContextCompaction(
            resolvedConversation.automaticCompactionResult,
            invocationID: invocationID,
        )
        return conversation
    }

    private func recordAutomaticContextCompaction(
        _ result: ContextCompactionResult,
        invocationID: InvocationID,
    ) async {
        if case .skipped(.disabled) = result {
            return
        }
        let info: AgentTraceEntry.Kind.ContextCompactionInfo = if shouldRecordAutomaticCompactionConfiguration(for: result) {
            conversationProvider.compactionTraceInfo(
                mode: .automatic,
                result: result,
            )
        } else {
            .init(mode: .automatic, result: result)
        }
        record(
            kind: .contextCompaction(info),
            invocationID: invocationID,
        )
    }

    private func shouldRecordAutomaticCompactionConfiguration(
        for result: ContextCompactionResult,
    ) -> Bool {
        switch result {
        case .compacted:
            return true
        case .skipped(let reason):
            switch reason {
            case .inferenceError, .failed, .sessionReleased, .noActiveConversation:
                return true
            case .disabled, .conversationReplaced, .triggerNotMet:
                return false
            }
        }
    }
}
