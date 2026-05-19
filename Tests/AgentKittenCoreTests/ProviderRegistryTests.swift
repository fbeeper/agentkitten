// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Suite("Provider Registry")
struct ProviderRegistryTests {
    @Test func defaultProviderReference_routesToRegistryDefault() async throws {
        let defaultProvider = ScriptedInferenceProvider(
            responses: [.success("Default answer")],
        )
        let conversation = try makeConversation(
            registry: ProviderRegistry(default: defaultProvider),
            provider: .default,
        )

        let completions = try await assistantCompletions(from: conversation)

        #expect(completions == ["Default answer"])
        #expect(await defaultProvider.script.executionSessionUseCount() == 1)
    }

    @Test func unregisteredProviderType_fallsBackToDefaultProvider() async throws {
        let defaultProvider = ScriptedInferenceProvider(
            responses: [.success("Default answer")],
        )
        let conversation = try makeConversation(
            registry: ProviderRegistry(default: defaultProvider),
            provider: .ofType(UnregisteredOverrideProvider.self),
        )

        let completions = try await assistantCompletions(from: conversation)

        #expect(completions == ["Default answer"])
        #expect(await defaultProvider.script.executionSessionUseCount() == 1)
    }

    @Test func registeredProviderReference_routesToOverrideProvider() async throws {
        let defaultProvider = ScriptedInferenceProvider(
            responses: [.success("Default answer")],
        )
        let overrideProvider = ScriptedInferenceProvider(
            responses: [.success("Override answer")],
        )
        let conversation = try makeConversation(
            registry: ProviderRegistry(default: defaultProvider)
                .registering(ExecutionOverrideProvider(base: overrideProvider)),
            provider: .ofType(ExecutionOverrideProvider.self),
        )

        let completions = try await assistantCompletions(from: conversation)

        #expect(completions == ["Override answer"])
        #expect(await defaultProvider.script.executionSessionUseCount() == 0)
        #expect(await overrideProvider.script.executionSessionUseCount() == 1)
    }

    @Test func register_replacesPriorRegistrationOfSameType() async throws {
        let defaultProvider = ScriptedInferenceProvider(
            responses: [.success("Unused default")],
        )
        let firstProvider = ScriptedInferenceProvider(
            responses: [.success("First override")],
        )
        let secondProvider = ScriptedInferenceProvider(
            responses: [.success("Second override")],
        )
        let conversation = try makeConversation(
            registry: ProviderRegistry(default: defaultProvider)
                .registering(ExecutionOverrideProvider(base: firstProvider))
                .registering(ExecutionOverrideProvider(base: secondProvider)),
            provider: .ofType(ExecutionOverrideProvider.self),
        )

        let completions = try await assistantCompletions(from: conversation)

        #expect(completions == ["Second override"])
        #expect(await firstProvider.script.executionSessionUseCount() == 0)
        #expect(await secondProvider.script.executionSessionUseCount() == 1)
        #expect(await defaultProvider.script.executionSessionUseCount() == 0)
    }
}

private func makeConversation(
    registry: ProviderRegistry,
    provider: ProviderReference,
) throws -> AnyConversation {
    let factory = ConversationAssembler(
        phaseBehaviors: .init(),
        providerRegistry: registry,
        baseSystemPrompt: "Base prompt",
        toolDefinition: .noTools,
        runtimeConfig: ToolBehavior().runtimeConfig,
        toolApprovalGate: ToolApprovalGate(),
    )
    return try factory.makeConversation(
        owner: UserID.local,
        executionConfiguration: EffectiveExecutionConfiguration(provider: provider),
    )
}

private func assistantCompletions(from conversation: AnyConversation) async throws -> [String] {
    let stream = try await conversation.send(
        userMessage: UserMessage(text: "hello"),
        executionConfiguration: EffectiveExecutionConfiguration(),
        toolExecutionContext: .empty,
    )
    var completions: [String] = []
    for try await event in stream {
        if case .result(let message) = event.kind {
            completions.append(message.text)
        }
    }
    return completions
}

private struct ExecutionOverrideProvider: InferenceProviding {
    typealias Session = ScriptedInferenceSession

    let base: ScriptedInferenceProvider

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> ScriptedInferenceSession {
        base.makeSession(
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            inferenceContext: inferenceContext,
        )
    }
}

private struct UnregisteredOverrideProvider: InferenceProviding {
    typealias Session = ScriptedInferenceSession

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> ScriptedInferenceSession {
        fatalError("Should not be called when lookup falls back to the default provider")
    }
}
