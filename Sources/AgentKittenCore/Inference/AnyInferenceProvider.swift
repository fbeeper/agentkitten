// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Type-erased inference provider used for provider registries on `Agent`.
///
/// Wrap concrete providers for storage in ``ProviderRegistry`` while keeping
/// concrete session types intact inside the erasure boundary.
struct AnyInferenceProvider: Sendable {
    let providerObjectIdentifier: ObjectIdentifier
    private let sessionCompatibilityClosure:
        @Sendable (
            EffectiveExecutionConfiguration,
            EffectiveExecutionConfiguration
        ) -> SessionCompatibility
    private let preflightClosure: @Sendable (ToolRegistry, ToolSelection) throws -> Void
    private let makeConversationClosure:
        @Sendable (
            UserID,
            String?,
            EffectiveExecutionConfiguration,
            ToolRuntime
        ) throws -> AnyConversation
    private let generateIsolatedClosure:
        @Sendable (String, InferenceConfiguration, InferenceContext) async throws -> String

    /// Wraps a concrete provider for storage in a registry.
    init<Provider: InferenceProviding>(_ provider: Provider) {
        let providerObjectIdentifier = ObjectIdentifier(Provider.self)
        self.providerObjectIdentifier = providerObjectIdentifier
        sessionCompatibilityClosure = { current, next in
            provider.sessionCompatibility(from: current, to: next)
        }
        preflightClosure = { toolRegistry, toolSelection in
            try provider.preflight(toolRegistry: toolRegistry, toolSelection: toolSelection)
        }
        makeConversationClosure = { owner, systemPrompt, executionConfiguration, toolRuntime in
            try provider.preflight(
                toolRegistry: toolRuntime.toolRegistry,
                toolSelection: executionConfiguration.toolSelection,
            )
            return AnyConversation(
                conversation: Conversation(
                    owner: owner,
                    provider: provider,
                    systemPrompt: systemPrompt ?? "",
                    executionConfiguration: executionConfiguration,
                    toolRuntime: toolRuntime,
                ),
            )
        }
        generateIsolatedClosure = { prompt, configuration, context in
            let toolBehavior = ToolBehavior()
            let session = provider.makeSession(
                systemPrompt: nil,
                toolRuntime: ToolRuntime(toolDefinition: .noTools, toolBehavior: toolBehavior),
                toolSelection: .disabled,
                inferenceContext: context,
            )
            let parameters = InferenceRequestParameters(
                configuration: configuration,
                toolSelection: .disabled,
            )
            let stream = try await session.run(UserMessage(text: prompt), parameters: parameters)
            for try await event in stream {
                if case .result(let text, _) = event {
                    return text
                }
            }
            throw InferenceError.invalidResponse("Summarization session produced no result.")
        }
    }

    func makeConversation(
        owner: UserID,
        systemPrompt: String?,
        executionConfiguration: EffectiveExecutionConfiguration,
        toolRuntime: ToolRuntime,
    ) throws -> AnyConversation {
        try makeConversationClosure(
            owner,
            systemPrompt,
            executionConfiguration,
            toolRuntime,
        )
    }

    func preflight(
        toolRegistry: ToolRegistry,
        toolSelection: ToolSelection,
    ) throws {
        try preflightClosure(toolRegistry, toolSelection)
    }

    func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility {
        sessionCompatibilityClosure(current, next)
    }

    func generateIsolated(
        prompt: String,
        configuration: InferenceConfiguration,
        inferenceContext: InferenceContext,
    ) async throws -> String {
        try await generateIsolatedClosure(prompt, configuration, inferenceContext)
    }
}
