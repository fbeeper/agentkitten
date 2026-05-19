// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Synchronization
import Testing

@Suite("Conversation Provider")
struct ConversationProviderTests {
    @Test func sameProviderInferenceChange_reusesConversation() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [
                .success("first"),
                .success("second"),
            ],
        )
        var conversationProvider = makeConversationProvider(
            registry: ProviderRegistry(default: provider),
        )

        let firstConversation = try await prepareConversation(
            &conversationProvider,
            for: EffectiveExecutionConfiguration(
                inferenceConfiguration: InferenceConfiguration(temperature: 0.1),
            ),
        )
        let secondConversation = try await prepareConversation(
            &conversationProvider,
            for: EffectiveExecutionConfiguration(
                inferenceConfiguration: InferenceConfiguration(temperature: 0.9),
            ),
        )

        let firstConversationID = try await conversationID(from: firstConversation)
        let secondConversationID = try await conversationID(from: secondConversation)

        #expect(firstConversationID == secondConversationID)
        #expect(await provider.script.executionSessionUseCount() == 1)
    }

    @Test func toolSelectionChange_rebuildsProviderSession_preservingConversationIdentity() async throws {
        let script = ScriptedInferenceProvider(
            responses: [
                .success("first"),
                .success("second"),
            ],
        )
        let provider = RebuildingProvider(base: script)
        var conversationProvider = makeConversationProvider(
            registry: ProviderRegistry(default: provider),
        )

        // Obtain and use the first conversation so provider session A is exercised.
        let firstConversation = try await prepareConversation(
            &conversationProvider,
            for: EffectiveExecutionConfiguration(),
        )
        let firstConversationID = try await conversationID(from: firstConversation)

        // Changing toolSelection rebuilds the provider session (session B) inside the
        // same conversation actor — the conversation identity is preserved.
        let secondConversation = try await prepareConversation(
            &conversationProvider,
            for: EffectiveExecutionConfiguration(toolSelection: .disabled),
        )
        let secondConversationID = try await conversationID(from: secondConversation)

        #expect(firstConversationID == secondConversationID)
        #expect(await script.script.executionSessionUseCount() == 2)
    }

    @Test func providerChange_replacesConversationWithoutSameProviderCompatibility() async throws {
        let defaultProvider = ScriptedInferenceProvider(
            responses: [.success("default")],
        )
        let overrideProvider = ScriptedInferenceProvider(
            responses: [.success("override")],
        )
        var conversationProvider = makeConversationProvider(
            registry: ProviderRegistry(default: defaultProvider)
                .registering(ExecutionOverrideProvider(base: overrideProvider)),
        )

        let firstConversation = try await prepareConversation(
            &conversationProvider,
            for: EffectiveExecutionConfiguration(),
        )
        let secondConversation = try await prepareConversation(
            &conversationProvider,
            for: EffectiveExecutionConfiguration(
                provider: .ofType(ExecutionOverrideProvider.self),
            ),
        )

        let firstConversationID = try await conversationID(from: firstConversation)
        let secondConversationID = try await conversationID(from: secondConversation)

        #expect(firstConversationID != secondConversationID)
        #expect(await defaultProvider.script.executionSessionUseCount() == 1)
        #expect(await overrideProvider.script.executionSessionUseCount() == 1)
    }

    @Test func initialProviderPreflightReceivesRegistryAndToolSelection() async throws {
        let recorder = PreflightRecorder()
        let provider = PreflightRecordingProvider(
            base: ScriptedInferenceProvider(responses: [.success("first")]),
            recorder: recorder,
        )
        var conversationProvider = makeConversationProvider(
            registry: ProviderRegistry(default: provider),
            toolDefinition: selectionTestToolDefinition(),
        )

        _ = try await prepareConversation(
            &conversationProvider,
            for: EffectiveExecutionConfiguration(toolSelection: .including(["counting_echo"])),
        )

        #expect(recorder.snapshots() == [
            PreflightSnapshot(
                toolNames: ["conversation_other", "counting_echo"],
                toolSelection: .including(["counting_echo"]),
            ),
        ])
    }

    @Test func rebuiltProviderPreflightReceivesRegistryAndToolSelection() async throws {
        let recorder = PreflightRecorder()
        let provider = PreflightRecordingProvider(
            base: ScriptedInferenceProvider(
                responses: [
                    .success("first"),
                    .success("second"),
                ],
            ),
            recorder: recorder,
            rebuildOnToolSelectionChange: true,
        )
        var conversationProvider = makeConversationProvider(
            registry: ProviderRegistry(default: provider),
            toolDefinition: selectionTestToolDefinition(),
        )

        _ = try await prepareConversation(
            &conversationProvider,
            for: EffectiveExecutionConfiguration(toolSelection: .all),
        )
        _ = try await prepareConversation(
            &conversationProvider,
            for: EffectiveExecutionConfiguration(toolSelection: .excluding(["conversation_other"])),
        )

        #expect(recorder.snapshots() == [
            PreflightSnapshot(
                toolNames: ["conversation_other", "counting_echo"],
                toolSelection: .all,
            ),
            PreflightSnapshot(
                toolNames: ["conversation_other", "counting_echo"],
                toolSelection: .excluding(["conversation_other"]),
            ),
        ])
    }

    @Test func send_turnOverridesOverrideReachesConversationPreparation() async throws {
        // Verifies that performTurn passes the turn's pre-merged executionEnvironment
        // (captured at enqueue time) to conversation preparation, not the session's
        // base agentEnvironment. If someone re-derives from the base without overlaying
        // the turn config, the toolSelection override is lost and sessionCompatibility
        // returns .reuse instead of .rebuildSession.
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: RebuildingProvider(
                base: ScriptedInferenceProvider(responses: [.success("First response."), .success("Second response.")]),
            )),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("First")
        _ = try await collectEvents(from: firstTurn)

        let secondTurn = try await session.send(
            "Second",
            turnOverrides: TurnOverrides(toolSelection: .disabled),
        )
        _ = try await collectEvents(from: secondTurn)

        let secondResolution = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))
        #expect(secondResolution.resolutionKind == .rebuildSession)
    }
}

private func makeConversationProvider(
    registry: ProviderRegistry,
    toolDefinition: ToolDefinition = .noTools,
) -> ConversationProvider {
    ConversationProvider(
        owner: .local,
        factory: ConversationAssembler(
            phaseBehaviors: .init(),
            providerRegistry: registry,
            baseSystemPrompt: "Base prompt",
            toolDefinition: toolDefinition,
            runtimeConfig: ToolBehavior().runtimeConfig,
            toolApprovalGate: ToolApprovalGate(),
        ),
    )
}

private func selectionTestToolDefinition() -> ToolDefinition {
    ToolDefinition(tools: [
        AnyAgentTool(CountingEchoTool(counter: ToolCallCounter())),
        AnyAgentTool(ConversationOtherTool()),
    ])
}

private func prepareConversation(
    _ conversationProvider: inout ConversationProvider,
    for turnOverrides: EffectiveExecutionConfiguration,
) async throws -> AnyConversation {
    let conversation = try await conversationProvider.resolveConversation(
        for: turnOverrides,
        automaticCompactionPolicy: .disabled,
    ).conversation
    let stream = try await conversation.send(
        userMessage: UserMessage(text: "hello"),
        executionConfiguration: turnOverrides,
        toolExecutionContext: .empty,
    )
    for try await _ in stream {}
    return conversation
}

private func conversationID(
    from conversation: AnyConversation,
) async throws -> ConversationID {
    await conversation.identity().conversationID
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

/// A provider that opts into `.rebuildSession` for `toolSelection` changes,
/// modelling the Apple provider's behaviour in tests that don't need the
/// full Apple stack.
private struct RebuildingProvider: InferenceProviding {
    typealias Session = ScriptedInferenceSession

    let base: ScriptedInferenceProvider

    nonisolated func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility {
        if current.provider != next.provider { return .replace }
        if current.toolSelection != next.toolSelection { return .rebuildSession }
        return .reuse
    }

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

private struct PreflightSnapshot: Sendable, Equatable {
    let toolNames: [String]
    let toolSelection: ToolSelection
}

private final class PreflightRecorder: @unchecked Sendable {
    private let snapshotsState = Mutex([PreflightSnapshot]())

    func record(_ registry: ToolRegistry, selection: ToolSelection) {
        snapshotsState.withLock {
            $0.append(PreflightSnapshot(
                toolNames: registry.all.map(\.name).sorted(),
                toolSelection: selection,
            ))
        }
    }

    func snapshots() -> [PreflightSnapshot] {
        snapshotsState.withLock { $0 }
    }
}

private struct PreflightRecordingProvider: InferenceProviding {
    typealias Session = ScriptedInferenceSession

    let base: ScriptedInferenceProvider
    let recorder: PreflightRecorder
    var rebuildOnToolSelectionChange = false

    nonisolated func preflight(
        toolRegistry: ToolRegistry,
        toolSelection: ToolSelection,
    ) throws {
        recorder.record(toolRegistry, selection: toolSelection)
    }

    nonisolated func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility {
        if current.provider != next.provider {
            return .replace
        }
        if rebuildOnToolSelectionChange, current.toolSelection != next.toolSelection {
            return .rebuildSession
        }
        return .reuse
    }

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

private struct ConversationOtherTool: AgentTool {
    struct Arguments: Codable, Sendable {}
    struct Output: Codable, Sendable {}

    static let name = "conversation_other"
    static let defaultDescription = "A second tool used for conversation provider selection tests."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(properties: [:], required: []))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output()
    }
}
