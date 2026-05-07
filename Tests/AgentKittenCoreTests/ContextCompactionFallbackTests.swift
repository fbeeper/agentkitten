// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore

@Test func automaticContextCompaction_failsTurnWhenUsageUnavailableOnReusePath() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: UsageUnavailableProvider()),
        behavior: AgentBehavior(
            systemPrompt: "Test",
            defaultAutomaticCompactionPolicy: .enabled()
        )
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("first")
    _ = try await collectEvents(from: firstTurn)

    let secondTurn = try await session.send("second")
    do {
        _ = try await collectEvents(from: secondTurn)
        Issue.record("Expected turn to fail with usage error")
    } catch {
        #expect(String(describing: error).contains("usage unavailable"))
    }
}

@Test func automaticContextCompaction_failsTurnWhenUsageUnavailableOnRebuildPath() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: UsageUnavailableRebuildProvider()),
        behavior: AgentBehavior(
            systemPrompt: "Test",
            defaultAutomaticCompactionPolicy: .enabled()
        )
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("first")
    _ = try await collectEvents(from: firstTurn)

    let secondTurn = try await session.send(
        "second",
        turnOverrides: TurnOverrides(toolSelection: .disabled)
    )
    do {
        _ = try await collectEvents(from: secondTurn)
        Issue.record("Expected turn to fail with usage error")
    } catch {
        #expect(String(describing: error).contains("usage unavailable"))
    }
}

private struct UsageUnavailableProvider: InferenceProviding {
    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) -> UsageUnavailableSession {
        UsageUnavailableSession()
    }
}

private struct UsageUnavailableRebuildProvider: InferenceProviding {
    nonisolated func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration
    ) -> SessionCompatibility {
        current.toolSelection == next.toolSelection ? .reuse : .rebuildSession
    }

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) -> UsageUnavailableSession {
        UsageUnavailableSession()
    }

    func makeSession(
        continuing session: UsageUnavailableSession,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) async throws -> UsageUnavailableSession {
        throw InferenceError.invalidResponse("rebuild failed")
    }
}

private actor UsageUnavailableSession: InferenceSession, StructuredInferenceSession {
    private var index = 0

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        index += 1
        let text = index == 1 ? "first response" : "second response"
        return AsyncThrowingStream { continuation in
            continuation.yield(.delta(text))
            continuation.yield(.result(text, .endTurn))
            continuation.finish()
        }
    }

    func contextUsage() async throws -> ContextUsage {
        throw InferenceError.invalidResponse("usage unavailable")
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        throw .generationFailed(InferenceError.invalidResponse("structured generation unsupported"))
    }
}
