// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Test func manualCompaction_usesBasePhaseBehaviorInferenceConfigurationByDefault() async throws {
    let compactionConfig = InferenceConfiguration(temperature: 0.1, maxTokens: 512)
    let behavior = AgentBehavior(
        systemPrompt: "Test",
        phaseBehaviors: PhaseBehaviorSet(base: PhaseBehavior(inferenceConfiguration: compactionConfig)),
    )
    let provider = CompactionConfigRecordingProvider()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: behavior,
    )
    let session = agent.makeSession()
    let turn = try await session.send("Hello")
    _ = try await collectEvents(from: turn)
    _ = try await session.compactContext(
        .summarize(ContextCompactionOptions.SummarizationOptions(preservedRecentTurnCount: 0)),
    )

    let recorded = await provider.recordedCompactionConfigurations()
    #expect(recorded == [compactionConfig])
    let trace = try #require(await firstManualContextCompaction(on: session))
    #expect(trace.provider == .default)
    #expect(trace.inferenceConfiguration == compactionConfig.traceSnapshot)
    #expect(trace.inferenceContext == nil)
}

@Test func compactionPhaseBehavior_overridesInferenceConfiguration() async throws {
    let baseConfig = InferenceConfiguration(temperature: 0.1, maxTokens: 512)
    let compactionConfig = InferenceConfiguration(temperature: 0.2, maxTokens: 256)
    var phaseBehaviors = PhaseBehaviorSet(base: PhaseBehavior(inferenceConfiguration: baseConfig))
    phaseBehaviors.set(
        PhaseBehavior(inferenceConfiguration: compactionConfig),
        for: .compaction,
    )
    let behavior = AgentBehavior(
        systemPrompt: "Test",
        phaseBehaviors: phaseBehaviors,
    )
    let provider = CompactionConfigRecordingProvider()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: behavior,
    )
    let session = agent.makeSession()
    let turn = try await session.send(
        "Hello",
        turnOverrides: TurnOverrides(inferenceConfiguration: InferenceConfiguration(temperature: 0.9)),
    )
    _ = try await collectEvents(from: turn)
    _ = try await session.compactContext(
        .summarize(ContextCompactionOptions.SummarizationOptions(preservedRecentTurnCount: 0)),
    )

    let recorded = await provider.recordedCompactionConfigurations()
    #expect(recorded == [compactionConfig])
    let trace = try #require(await firstManualContextCompaction(on: session))
    #expect(trace.provider == .default)
    #expect(trace.inferenceConfiguration == compactionConfig.traceSnapshot)
}

@Test func compactionPhaseBehavior_providerOverrideRoutesSummaryGenerationThroughOverrideProvider() async throws {
    let defaultProvider = CompactionConfigRecordingProvider()
    let overrideProvider = CompactionConfigRecordingProvider()
    var phaseBehaviors = PhaseBehaviorSet()
    phaseBehaviors.set(
        PhaseBehavior(
            provider: .ofType(CompactionOverrideProvider.self),
            inferenceConfiguration: InferenceConfiguration(temperature: 0.4, maxTokens: 111),
        ),
        for: .compaction,
    )
    let behavior = AgentBehavior(systemPrompt: "Test", phaseBehaviors: phaseBehaviors)
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: defaultProvider)
            .registering(CompactionOverrideProvider(base: overrideProvider)),
        behavior: behavior,
    )
    let session = agent.makeSession()
    let turn = try await session.send("Hello")
    _ = try await collectEvents(from: turn)
    _ = try await session.compactContext(
        .summarize(ContextCompactionOptions.SummarizationOptions(preservedRecentTurnCount: 0)),
    )

    #expect(await defaultProvider.recordedCompactionConfigurations().isEmpty)
    #expect(await overrideProvider.recordedCompactionConfigurations() == [
        InferenceConfiguration(temperature: 0.4, maxTokens: 111),
    ])
    let trace = try #require(await firstManualContextCompaction(on: session))
    #expect(trace.provider == .named(String(describing: CompactionOverrideProvider.self)))
    #expect(trace.inferenceConfiguration == InferenceConfiguration(
        temperature: 0.4,
        maxTokens: 111,
    ).traceSnapshot)
}

@Test func compaction_forwardsInferenceContextToSummarySession() async throws {
    let provider = ContextRecordingProvider()
    var phaseBehaviors = PhaseBehaviorSet()
    phaseBehaviors.base[SentinelContextKey.self] = "sentinel-value"
    phaseBehaviors.base[AnotherSentinelContextKey.self] = "another-value"
    let behavior = AgentBehavior(systemPrompt: "Test", phaseBehaviors: phaseBehaviors)
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: behavior,
    )
    let session = agent.makeSession()

    let turn = try await session.send("Hello")
    _ = try await collectEvents(from: turn)
    _ = try await session.compactContext(
        .summarize(ContextCompactionOptions.SummarizationOptions(preservedRecentTurnCount: 0)),
    )

    let recorded = await provider.recordedSummaryContexts()
    #expect(recorded.count == 1)
    #expect(recorded.first?[SentinelContextKey.self] == "sentinel-value")
    #expect(recorded.first?[AnotherSentinelContextKey.self] == "another-value")
    let trace = try #require(await firstManualContextCompaction(on: session))
    #expect(trace.inferenceContext == CustomContextSnapshot(entries: [
        CustomContextSnapshot.Entry(key: AnotherSentinelContextKey.id, valueSummary: "another-value"),
        CustomContextSnapshot.Entry(key: SentinelContextKey.id, valueSummary: "sentinel-value"),
    ]))
}

@Test func compaction_splitsOnContextWindowExceededFromSummarySession() async throws {
    let provider = SplittingCompactionProvider()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let turn = try await session.send("Hello")
    _ = try await collectEvents(from: turn)
    let result = try await session.compactContext(
        .summarize(ContextCompactionOptions.SummarizationOptions(preservedRecentTurnCount: 0)),
    )

    #expect(result.didCompact)
    let callCount = await provider.summarizationCallCount()
    // First call fails (both turns together), then two individual calls succeed
    #expect(callCount == 3)
}
