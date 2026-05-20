// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Test func contextUsage_throwsWithoutActiveConversation() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider()),
        behavior: .test(),
    )
    let session = agent.makeSession()

    do {
        _ = try await session.contextUsage()
        Issue.record("Expected AgentSessionError.noActiveConversation")
    } catch AgentSessionError.noActiveConversation {}
}

@Test func contextUsage_returnsActiveProviderUsageAfterTurn() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider(responses: [
            "First response.",
        ])),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let turn = try await session.send("First")
    _ = try await collectEvents(from: turn)

    let usage = try await session.contextUsage()

    #expect(usage.contextTokens > 0)
    #expect(usage.contextSize == 100)
}

@Test func compactContext_recordsManualCompactionAndPreservesConversation() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider(responses: [
            "First response.",
            "Second response.",
        ])),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)

    let result = try await session.compactContext()
    let compactedResult = try #require(result.compacted)
    #expect(compactedResult.usageBefore.contextTokens >= compactedResult.usageAfter.contextTokens)

    let secondTurn = try await session.send("Second")
    _ = try await collectEvents(from: secondTurn)

    let manualCompaction = try #require(await firstContextCompaction(on: session, mode: .manual))
    let firstResolution = try #require(await conversationResolvedEntry(for: firstTurn.id, on: session))
    let secondResolution = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))

    #expect(manualCompaction.result.compacted != nil)
    #expect(manualCompaction.provider == .default)
    #expect(manualCompaction.inferenceConfiguration == InferenceConfiguration().traceSnapshot)
    #expect(manualCompaction.inferenceContext == nil)
    #expect(firstResolution.identity.conversationID == secondResolution.identity.conversationID)
}

@Test func compactContext_withoutActiveConversationRecordsSkippedResult() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider()),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let result = try await session.compactContext()
    let manualCompaction = try #require(await firstContextCompaction(on: session, mode: .manual))

    #expect(result == .skipped(.noActiveConversation))
    #expect(manualCompaction.result == .skipped(.noActiveConversation))
    #expect(manualCompaction.provider == .default)
    #expect(manualCompaction.inferenceConfiguration == InferenceConfiguration().traceSnapshot)
    #expect(manualCompaction.inferenceContext == nil)
}

@Test func automaticContextCompaction_runsBeforeTurnWhenThresholdIsMet() async throws {
    let behavior = AgentBehavior(
        systemPrompt: "Test",
        defaultAutomaticCompactionPolicy: .enabled(
            trigger: .percentOfContextWindow(0.01),
            options: ContextCompactionOptions(),
        ),
    )
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider(responses: [
            "First response.",
            "Second response.",
        ])),
        behavior: behavior,
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)
    let firstCompaction = try #require(await contextCompaction(
        on: session,
        mode: .automatic,
        invocationID: firstTurn.id,
    ))
    #expect(firstCompaction.result == .skipped(.conversationReplaced))

    let secondTurn = try await session.send("Second")
    _ = try await collectEvents(from: secondTurn)

    let secondEntries = await rawTraceEntries(for: secondTurn.id, on: session)
    let resolutionIndex = try #require(secondEntries.firstIndex {
        if case .conversationResolved = $0.kind {
            return true
        }
        return false
    })
    let compactionIndex = try #require(secondEntries.firstIndex {
        if case .contextCompaction(let info) = $0.kind {
            return info.mode == .automatic
        }
        return false
    })
    let turnStartedIndex = try #require(secondEntries.firstIndex {
        if case .turnStarted = $0.kind {
            return true
        }
        return false
    })

    #expect(resolutionIndex < compactionIndex)
    #expect(compactionIndex < turnStartedIndex)
}

@Test func automaticContextCompaction_recordsSkippedWhenThresholdIsNotMet() async throws {
    let behavior = AgentBehavior(
        systemPrompt: "Test",
        defaultAutomaticCompactionPolicy: .enabled(
            trigger: .percentOfContextWindow(0.99),
            options: ContextCompactionOptions(),
        ),
    )
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider(responses: [
            "First response.",
            "Second response.",
        ])),
        behavior: behavior,
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)
    let secondTurn = try await session.send("Second")
    _ = try await collectEvents(from: secondTurn)

    let compaction = try #require(await contextCompaction(
        on: session,
        mode: .automatic,
        invocationID: secondTurn.id,
    ))
    guard case .skipped(.triggerNotMet(let usage)) = compaction.result else {
        Issue.record("Expected automatic compaction to record trigger-not-met skip")
        return
    }
    #expect(usage.contextTokens < 99)
    #expect(compaction.provider == nil)
    #expect(compaction.inferenceConfiguration == nil)
    #expect(compaction.inferenceContext == nil)
}

@Test func automaticContextCompaction_runsWhenConfigurationChangesButConversationReuses() async throws {
    let behavior = AgentBehavior(
        systemPrompt: "Test",
        defaultAutomaticCompactionPolicy: .enabled(
            trigger: .percentOfContextWindow(0.01),
            options: ContextCompactionOptions(),
        ),
    )
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider(responses: [
            "First response.",
            "Second response.",
        ])),
        behavior: behavior,
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)
    let secondTurn = try await session.send(
        "Second",
        turnOverrides: TurnOverrides(
            inferenceConfiguration: InferenceConfiguration(maxTokens: 128),
        ),
    )
    _ = try await collectEvents(from: secondTurn)

    let compaction = try #require(await contextCompaction(
        on: session,
        mode: .automatic,
        invocationID: secondTurn.id,
    ))
    let resolution = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))
    #expect(compaction.result.didCompact)
    #expect(compaction.provider == .default)
    #expect(compaction.inferenceConfiguration == InferenceConfiguration().traceSnapshot)
    #expect(compaction.inferenceContext == nil)
    #expect(resolution.resolutionKind == .reuse)
}

@Test func automaticContextCompaction_runsWhenConversationRebuildsSession() async throws {
    let behavior = AgentBehavior(
        systemPrompt: "Test",
        defaultAutomaticCompactionPolicy: .enabled(
            trigger: .percentOfContextWindow(0.01),
            options: ContextCompactionOptions(),
        ),
    )
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: RebuildingMockProvider(responses: [
            "First response.",
            "Second response.",
        ])),
        behavior: behavior,
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)
    let secondTurn = try await session.send(
        "Second",
        turnOverrides: TurnOverrides(toolSelection: .disabled),
    )
    _ = try await collectEvents(from: secondTurn)

    let compaction = try #require(await contextCompaction(
        on: session,
        mode: .automatic,
        invocationID: secondTurn.id,
    ))
    let firstResolution = try #require(await conversationResolvedEntry(for: firstTurn.id, on: session))
    let secondResolution = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))

    #expect(compaction.result.didCompact)
    #expect(secondResolution.resolutionKind == .rebuildSession)
    #expect(firstResolution.identity.conversationID == secondResolution.identity.conversationID)
    #expect(firstResolution.identity.inferenceSessionID != secondResolution.identity.inferenceSessionID)
}

@Test func automaticContextCompaction_skipsWhenConversationIsReplaced() async throws {
    let behavior = AgentBehavior(
        systemPrompt: "Test",
        defaultAutomaticCompactionPolicy: .enabled(
            trigger: .percentOfContextWindow(0.01),
            options: ContextCompactionOptions(),
        ),
    )
    let replacement = ReplacementMockProvider(responses: ["Replacement response."])
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider(responses: [
            "First response.",
        ])).registering(replacement),
        behavior: behavior,
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)
    let secondTurn = try await session.send(
        "Second",
        turnOverrides: TurnOverrides(
            provider: .ofType(ReplacementMockProvider.self),
        ),
    )
    _ = try await collectEvents(from: secondTurn)

    let compaction = try #require(await contextCompaction(
        on: session,
        mode: .automatic,
        invocationID: secondTurn.id,
    ))
    let resolution = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))
    #expect(resolution.resolutionKind == .replace)
    #expect(compaction.result == .skipped(.conversationReplaced))
}

@Test func automaticCompactionPolicy_canBeUpdatedOnSession() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider(responses: [
            "First response.",
            "Second response.",
        ])),
        behavior: .test(),
    )
    let session = agent.makeSession()

    #expect(await session.automaticCompactionPolicy == .disabled)
    await session.setAutomaticCompactionPolicy(.enabled(
        trigger: .percentOfContextWindow(0.01),
        options: ContextCompactionOptions(),
    ))

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)
    let secondTurn = try await session.send("Second")
    _ = try await collectEvents(from: secondTurn)

    #expect(await session.automaticCompactionPolicy != .disabled)
    let firstCompaction = try #require(await contextCompaction(
        on: session,
        mode: .automatic,
        invocationID: firstTurn.id,
    ))
    let secondCompaction = try #require(await contextCompaction(
        on: session,
        mode: .automatic,
        invocationID: secondTurn.id,
    ))
    #expect(firstCompaction.result == .skipped(.conversationReplaced))
    #expect(secondCompaction.result.didCompact)
}

private func firstContextCompaction(
    on session: AgentSession,
    mode: AgentTraceEntry.Kind.ContextCompactionInfo.Mode,
) async -> AgentTraceEntry.Kind.ContextCompactionInfo? {
    let trace = await session.trace
    for entry in await trace.snapshot() {
        if case .contextCompaction(let info) = entry.kind, info.mode == mode {
            return info
        }
    }
    return nil
}

private func contextCompaction(
    on session: AgentSession,
    mode: AgentTraceEntry.Kind.ContextCompactionInfo.Mode,
    invocationID: InvocationID,
) async -> AgentTraceEntry.Kind.ContextCompactionInfo? {
    for entry in await rawTraceEntries(for: invocationID, on: session) {
        if case .contextCompaction(let info) = entry.kind, info.mode == mode {
            return info
        }
    }
    return nil
}

extension ContextCompactionResult {
    fileprivate var compacted: ContextCompactionResult.Compacted? {
        guard case .compacted(let compacted) = self else {
            return nil
        }
        return compacted
    }
}
