// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

@Suite("AgentTrace")
struct TraceTests {
    @Test func directExecution_recordsMessageThenCompleted() async throws {
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                responses: [.success("Direct answer")],
            )),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello")
        _ = try await collectEvents(from: turn)

        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "Direct answer"))),
            .turnCompleted(.completed),
        ])
    }

    @Test func traceGrowsAcrossTurns() async throws {
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                responses: [
                    .success("First"),
                    .success("Second"),
                ],
            )),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("First")
        _ = try await collectEvents(from: firstTurn)
        let secondTurn = try await session.send("Second")
        _ = try await collectEvents(from: secondTurn)

        let trace = await session.trace
        let allEntries = await trace.snapshot()
        #expect(allEntries.contains { $0.invocationID == firstTurn.id })
        #expect(allEntries.contains { $0.invocationID == secondTurn.id })
    }

    @Test func liveStreamYieldsEntries() async throws {
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                responses: [.success("Direct answer")],
            )),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello")
        let trace = await session.trace
        let stream = trace.observe()
        let streamTask = Task<[AgentTraceEntry], Never> {
            var collected: [AgentTraceEntry] = []
            for await entry in stream {
                guard entry.invocationID == turn.id else {
                    continue
                }
                collected.append(entry)
                if case .turnCompleted = entry.kind {
                    return collected
                }
            }
            return collected
        }

        _ = try await collectEvents(from: turn)
        let streamed = await streamTask.value
        let snapshot = await rawTraceEntries(for: turn.id, on: session)

        #expect(streamed == snapshot)
    }

    @Test func cancelledTurn_recordsCancelledOutcome() async throws {
        let provider = HangingInferenceProvider()
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Cancel me")
        let eventsTask = Task {
            try await collectEvents(from: turn)
        }
        await provider.waitUntilStarted()
        await turn.cancel()
        _ = try await eventsTask.value

        let kinds = directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session))
        #expect(kinds.contains(.turnCompleted(.cancelled)))
        #expect(!kinds.contains(.turnCompleted(.completed)))
        #expect(!kinds.contains(where: whereFailedTurnCompleted))
    }

    @Test func failedTurn_recordsErrorThenFailedOutcome() async throws {
        let failure = InferenceError.invalidResponse("provider failure")
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                responses: [.failure(failure)],
            )),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Fail")
        await #expect(throws: Error.self) {
            _ = try await collectEvents(from: turn)
        }

        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Fail")),
            .error(AgentTraceEntry.Kind.ErrorInfo(failure)),
            .turnCompleted(.failed(AgentTraceEntry.Kind.ErrorInfo(failure))),
        ])
    }

    @Test func conversationResolved_recordsEffectiveConversation() async throws {
        let defaultProvider = ScriptedInferenceProvider(
            responses: [.success("Default answer")],
        )
        let overrideProvider = ScriptedInferenceProvider(
            responses: [.success("Override answer")],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: defaultProvider)
                .registering(TraceExecutionOverrideProvider(base: overrideProvider)),
            behavior: .test(),
        )
        let session = agent.makeSession()

        var turnOverrides = TurnOverrides(
            toolSelection: .disabled,
            toolStepBudget: .disabled,
            inferenceConfiguration: InferenceConfiguration(
                temperature: 0.2,
                maxTokens: 128,
            ),
            provider: .ofType(TraceExecutionOverrideProvider.self),
        )
        turnOverrides[TraceInferenceContextKey.self] = "trace-model"
        let turn = try await session.send("Hello", turnOverrides: turnOverrides)
        _ = try await collectEvents(from: turn)

        let resolution = try #require(await conversationResolvedEntry(for: turn.id, on: session))
        let preparation = try #require(await executionPreparationEntry(for: turn.id, on: session))
        #expect(resolution.resolutionKind == .replace)
        #expect(preparation.verdict == .replace)
        #expect(preparation.turnOverrides?.toolSelection == .disabled)
        #expect(preparation.turnOverrides?.toolStepBudget == .disabled)
        let expectedInference = InferenceConfigurationSnapshot(temperature: 0.2, maxTokens: 128)
        #expect(preparation.turnOverrides?.inferenceConfiguration == expectedInference)
        #expect(preparation.inferenceContext == CustomContextSnapshot(entries: [
            CustomContextSnapshot.Entry(key: TraceInferenceContextKey.id, valueSummary: "trace-model"),
        ]))
    }

    @Test func conversationResolved_rebuildChangesInferenceSessionOnly() async throws {
        let script = ScriptedInferenceProvider(
            responses: [.success("First"), .success("Second")],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: TraceRebuildingProvider(base: script)),
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

        let first = try #require(await conversationResolvedEntry(for: firstTurn.id, on: session))
        let second = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))
        #expect(first.resolutionKind == .replace)
        #expect(second.resolutionKind == .rebuildSession)
        #expect(first.identity.conversationID == second.identity.conversationID)
        #expect(first.identity.inferenceSessionID != second.identity.inferenceSessionID)
    }

    @Test func conversationResolved_reuseKeepsBothIDsStable() async throws {
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                responses: [.success("First"), .success("Second")],
            )),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("First")
        _ = try await collectEvents(from: firstTurn)
        // Compatibility is decided from the effective execution configuration. With the default
        // provider, inference-configuration differences like temperature do not force rebuild or
        // replacement, so this override still reuses the same conversation and provider session.
        let secondTurn = try await session.send(
            "Second",
            turnOverrides: TurnOverrides(
                inferenceConfiguration: InferenceConfiguration(temperature: 0.1),
            ),
        )
        _ = try await collectEvents(from: secondTurn)

        let first = try #require(await conversationResolvedEntry(for: firstTurn.id, on: session))
        let second = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))
        #expect(second.resolutionKind == .reuse)
        #expect(first.identity.conversationID == second.identity.conversationID)
        #expect(first.identity.inferenceSessionID == second.identity.inferenceSessionID)
    }

    @Test func conversationResolutionFailureRecordsOnlyErrorAndTurnCompletion() async throws {
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: TraceFailingProvider()),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello")
        await #expect(throws: Error.self) {
            _ = try await collectEvents(from: turn)
        }

        #expect(await executionPreparationEntry(for: turn.id, on: session) == nil)
        #expect(await conversationResolvedEntry(for: turn.id, on: session) == nil)

        let failure = AgentTraceEntry.Kind.ErrorInfo(
            InferenceError.invalidResponse("preflight failed"),
        )
        #expect((await rawTraceEntries(for: turn.id, on: session)).map(\.kind) == [
            .error(failure),
            .turnCompleted(.failed(failure)),
        ])
    }
}

private enum TraceInferenceContextKey: ExecutionConfigurationKey {
    static let domains: Set<ExecutionConfigurationDomain> = [.inference]
    typealias Value = String
}

private struct TraceExecutionOverrideProvider: InferenceProviding {
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

private struct TraceRebuildingProvider: InferenceProviding {
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

private struct TraceFailingProvider: InferenceProviding {
    typealias Session = ScriptedInferenceSession

    let base = ScriptedInferenceProvider(
        responses: [.success("unused")],
    )

    func preflight(
        toolRegistry: ToolRegistry,
        toolSelection: ToolSelection,
    ) throws {
        throw InferenceError.invalidResponse("preflight failed")
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
