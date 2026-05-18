// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct ConversationAssembler: Sendable {
    private let phaseBehaviors: PhaseBehaviorSet
    private let providerRegistry: ProviderRegistry
    private let baseSystemPrompt: String
    private let toolDefinition: ToolDefinition
    private let rationaleSchemaDescription: String
    private let toolApprovalGate: ToolApprovalGate

    init(
        phaseBehaviors: PhaseBehaviorSet,
        providerRegistry: ProviderRegistry,
        baseSystemPrompt: String,
        toolDefinition: ToolDefinition,
        rationaleSchemaDescription: String,
        toolApprovalGate: ToolApprovalGate,
    ) {
        self.phaseBehaviors = phaseBehaviors
        self.providerRegistry = providerRegistry
        self.baseSystemPrompt = baseSystemPrompt
        self.toolDefinition = toolDefinition
        self.rationaleSchemaDescription = rationaleSchemaDescription
        self.toolApprovalGate = toolApprovalGate
    }

    func makeConversation(
        owner: UserID,
        executionConfiguration: EffectiveExecutionConfiguration,
    ) throws -> AnyConversation {
        let provider = resolveProvider(executionConfiguration: executionConfiguration)
        let toolRuntime = ToolRuntime(
            configuration: toolDefinition,
            rationaleSchemaDescription: rationaleSchemaDescription,
            approvalGate: toolApprovalGate,
        )
        return try provider.makeConversation(
            owner: owner,
            systemPrompt: baseSystemPrompt,
            executionConfiguration: executionConfiguration,
            toolRuntime: toolRuntime,
        )
    }

    /// Rebuilds the provider session on `conversation`, preserving its identity and history.
    ///
    /// Constructs a fresh ``ToolRuntime``, runs provider preflight, then delegates to
    /// ``AnyConversation/rebuildSession(toolRuntime:toolSelection:)``.
    func updateConversationSession(
        _ conversation: AnyConversation,
        for executionConfiguration: EffectiveExecutionConfiguration,
    ) async throws {
        let toolRuntime = ToolRuntime(
            configuration: toolDefinition,
            rationaleSchemaDescription: rationaleSchemaDescription,
            approvalGate: toolApprovalGate,
        )
        try resolveProvider(executionConfiguration: executionConfiguration)
            .preflight(
                toolRegistry: toolRuntime.toolRegistry,
                toolSelection: executionConfiguration.toolSelection,
            )
        try await conversation.rebuildSession(
            toolRuntime: toolRuntime,
            toolSelection: executionConfiguration.toolSelection,
            inferenceContext: executionConfiguration.inferenceContext,
        )
    }

    /// Rebuilds the provider session, applying automatic compaction as part of
    /// the rebuild when the policy requires it.
    func updateConversationSession(
        _ conversation: AnyConversation,
        for executionConfiguration: EffectiveExecutionConfiguration,
        automaticCompactionPolicy: AutomaticCompactionPolicy,
    ) async throws -> ContextCompactionResult {
        let decision = try await AutomaticCompactionOperation.decision(
            conversation,
            policy: automaticCompactionPolicy,
        )

        switch decision {
        case .skip(let result):
            try await updateConversationSession(conversation, for: executionConfiguration)
            return result
        case .compact(let options):
            return try await updateConversationSession(
                conversation,
                for: executionConfiguration,
                compacting: options,
            )
        }
    }

    func resolvedProviderObjectIdentifier(
        for executionConfiguration: EffectiveExecutionConfiguration,
    ) -> ObjectIdentifier {
        resolveProvider(executionConfiguration: executionConfiguration).providerObjectIdentifier
    }

    func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility {
        resolveProvider(executionConfiguration: current).sessionCompatibility(
            from: current,
            to: next,
        )
    }

    private func resolveProvider(
        executionConfiguration: EffectiveExecutionConfiguration,
    ) -> AnyInferenceProvider {
        providerRegistry.resolve(executionConfiguration.provider)
    }

    func makeSummaryGenerator() -> ContextCompactionSummaryGenerator {
        let phaseBehavior = phaseBehaviors.behavior(for: .compaction)
        let provider = providerRegistry.resolve(phaseBehavior.provider)
        let configuration = phaseBehavior.inferenceConfiguration
        let inferenceContext = phaseBehavior.inferenceContext
        return { prompt in
            try await provider.generateIsolated(
                prompt: prompt,
                configuration: configuration,
                inferenceContext: inferenceContext,
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func compactionTraceInfo(
        mode: AgentTraceEntry.Kind.ContextCompactionInfo.Mode,
        result: ContextCompactionResult,
    ) -> AgentTraceEntry.Kind.ContextCompactionInfo {
        let phaseBehavior = phaseBehaviors.behavior(for: .compaction)
        return AgentTraceEntry.Kind.ContextCompactionInfo(
            mode: mode,
            provider: phaseBehavior.provider.traceSnapshot,
            inferenceConfiguration: phaseBehavior.inferenceConfiguration.traceSnapshot,
            inferenceContext: phaseBehavior.inferenceContext.traceSnapshot,
            result: result,
        )
    }

    private func updateConversationSession(
        _ conversation: AnyConversation,
        for executionConfiguration: EffectiveExecutionConfiguration,
        compacting options: ContextCompactionOptions,
    ) async throws -> ContextCompactionResult {
        let toolRuntime = ToolRuntime(
            configuration: toolDefinition,
            rationaleSchemaDescription: rationaleSchemaDescription,
            approvalGate: toolApprovalGate,
        )
        try resolveProvider(executionConfiguration: executionConfiguration)
            .preflight(
                toolRegistry: toolRuntime.toolRegistry,
                toolSelection: executionConfiguration.toolSelection,
            )
        return try await conversation.rebuildSession(
            compacting: options,
            summaryGenerator: makeSummaryGenerator(),
            toolRuntime: toolRuntime,
            toolSelection: executionConfiguration.toolSelection,
            inferenceContext: executionConfiguration.inferenceContext,
        )
    }
}
