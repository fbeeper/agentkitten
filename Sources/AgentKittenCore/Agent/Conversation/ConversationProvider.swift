// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Session-owned direct conversation source.
///
/// This type is intentionally not `Sendable`. It keeps mutable cached
/// conversation state and is safe only because ``AgentSession`` is the sole
/// owner and accesses it under actor isolation.
struct ConversationProvider {
    struct ConversationResolutionResult {
        let conversation: AnyConversation
        let resolutionKind: Kind
        let automaticCompactionResult: ContextCompactionResult

        enum Kind {
            case reuse
            case rebuildSession
            case replace
        }
    }

    private let owner: UserID
    private let assembler: ConversationAssembler
    private var activeConversation: ActiveConversation?

    init(
        owner: UserID,
        factory: ConversationAssembler
    ) {
        self.owner = owner
        self.assembler = factory
    }

    mutating func clearActiveConversation() {
        activeConversation = nil
    }

    func compactActiveConversation(
        options: ContextCompactionOptions
    ) async throws -> ContextCompactionResult? {
        guard let activeConversation else {
            return nil
        }
        return try await activeConversation.conversation.compactContext(
            options: options,
            summaryGenerator: assembler.makeSummaryGenerator()
        )
    }

    func compactionTraceInfo(
        mode: AgentTraceEntry.Kind.ContextCompactionInfo.Mode,
        result: ContextCompactionResult
    ) -> AgentTraceEntry.Kind.ContextCompactionInfo {
        assembler.compactionTraceInfo(mode: mode, result: result)
    }

    mutating func resolveConversation(
        for executionConfiguration: EffectiveExecutionConfiguration,
        automaticCompactionPolicy: AutomaticCompactionPolicy
    ) async throws -> ConversationResolutionResult {
        switch preliminaryResolutionKind(for: executionConfiguration) {
        case .reuse:
            return try await resolveExistingConversation(
                for: executionConfiguration,
                plannedKind: .reuse,
                automaticCompactionPolicy: automaticCompactionPolicy
            )
        case .rebuildSession:
            return try await resolveExistingConversation(
                for: executionConfiguration,
                plannedKind: .rebuildSession,
                automaticCompactionPolicy: automaticCompactionPolicy
            )
        case .replace:
            let conversation = try assembler.makeConversation(
                owner: owner,
                executionConfiguration: executionConfiguration
            )
            activeConversation = ActiveConversation(
                executionConfiguration: executionConfiguration,
                conversation: conversation
            )
            return ConversationResolutionResult(
                conversation: conversation,
                resolutionKind: .replace,
                automaticCompactionResult: .skipped(.conversationReplaced)
            )
        }
    }

    /// Returns a preliminary resolution kind based on turn configuration alone,
    /// without considering what may happen during compaction. The final
    /// ``ConversationResolutionResult/resolutionKind`` is determined after
    /// compaction by inspecting the conversation identity.
    private func preliminaryResolutionKind(
        for executionConfiguration: EffectiveExecutionConfiguration
    ) -> ConversationResolutionResult.Kind {
        guard let activeConversation else {
            return .replace
        }
        if activeConversation.executionConfiguration == executionConfiguration {
            return .reuse
        }

        let currentProvider = assembler.resolvedProviderObjectIdentifier(
            for: activeConversation.executionConfiguration
        )
        let nextProvider = assembler.resolvedProviderObjectIdentifier(
            for: executionConfiguration
        )
        guard currentProvider == nextProvider else {
            return .replace
        }

        switch assembler.sessionCompatibility(
            from: activeConversation.executionConfiguration,
            to: executionConfiguration
        ) {
        case .reuse:
            return .reuse
        case .rebuildSession:
            return .rebuildSession
        case .replace:
            return .replace
        }
    }

    private mutating func resolveExistingConversation(
        for executionConfiguration: EffectiveExecutionConfiguration,
        plannedKind: ConversationResolutionResult.Kind,
        automaticCompactionPolicy: AutomaticCompactionPolicy
    ) async throws -> ConversationResolutionResult {
        let conversation = resolvedActiveConversation
        let identityBeforeResolution = await conversation.identity()
        let compaction = try await contextCompactionForExistingConversation(
            conversation,
            plannedKind: plannedKind,
            executionConfiguration: executionConfiguration,
            automaticCompactionPolicy: automaticCompactionPolicy
        )
        let resolvedKind = await resolvedKind(
            plannedKind: plannedKind,
            existingIdentity: identityBeforeResolution,
            conversation: conversation
        )
        activeConversation = ActiveConversation(
            executionConfiguration: executionConfiguration,
            conversation: conversation
        )
        return ConversationResolutionResult(
            conversation: conversation,
            resolutionKind: resolvedKind,
            automaticCompactionResult: compaction
        )
    }

    private func contextCompactionForExistingConversation(
        _ conversation: AnyConversation,
        plannedKind: ConversationResolutionResult.Kind,
        executionConfiguration: EffectiveExecutionConfiguration,
        automaticCompactionPolicy: AutomaticCompactionPolicy
    ) async throws -> ContextCompactionResult {
        switch plannedKind {
        case .reuse:
            return try await AutomaticCompactionOperation.compactIfNeeded(
                conversation,
                policy: automaticCompactionPolicy,
                summaryGenerator: assembler.makeSummaryGenerator()
            )
        case .rebuildSession:
            return try await assembler.updateConversationSession(
                conversation,
                for: executionConfiguration,
                automaticCompactionPolicy: automaticCompactionPolicy
            )
        case .replace:
            preconditionFailure("Replacement conversations are not resolved from an existing conversation")
        }
    }

    private func resolvedKind(
        plannedKind: ConversationResolutionResult.Kind,
        existingIdentity: ConversationIdentity,
        conversation: AnyConversation
    ) async -> ConversationResolutionResult.Kind {
        let resolvedIdentity = await conversation.identity()
        if resolvedIdentity.conversationID != existingIdentity.conversationID {
            return .replace
        }
        if resolvedIdentity.inferenceSessionID != existingIdentity.inferenceSessionID {
            return .rebuildSession
        }
        return plannedKind
    }

}

private struct ActiveConversation {
    var executionConfiguration: EffectiveExecutionConfiguration
    let conversation: AnyConversation
}

extension ConversationProvider {
    private var resolvedActiveConversation: AnyConversation {
        guard let activeConversation else {
            preconditionFailure("Conversation resolution requires an active conversation")
        }
        return activeConversation.conversation
    }

    func contextUsage() async throws -> ContextUsage {
        guard let activeConversation else {
            throw AgentSessionError.noActiveConversation
        }
        return try await activeConversation.conversation.contextUsage()
    }
}
