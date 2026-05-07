// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore

@Test func manualCompaction_usesBasePhaseBehaviorInferenceConfigurationByDefault() async throws {
    let compactionConfig = InferenceConfiguration(temperature: 0.1, maxTokens: 512)
    let behavior = AgentBehavior(
        systemPrompt: "Test",
        phaseBehaviors: .init(base: .init(inferenceConfiguration: compactionConfig))
    )
    let provider = CompactionConfigRecordingProvider()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: behavior
    )
    let session = agent.makeSession()

    let turn = try await session.send("Hello")
    _ = try await collectEvents(from: turn)
    _ = try await session.compactContext(.summarize(.init(preservedRecentTurnCount: 0)))

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
    var phaseBehaviors = PhaseBehaviorSet(base: .init(inferenceConfiguration: baseConfig))
    phaseBehaviors.set(
        .init(inferenceConfiguration: compactionConfig),
        for: .compaction
    )
    let behavior = AgentBehavior(
        systemPrompt: "Test",
        phaseBehaviors: phaseBehaviors
    )
    let provider = CompactionConfigRecordingProvider()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: behavior
    )
    let session = agent.makeSession()

    let turn = try await session.send(
        "Hello",
        turnOverrides: TurnOverrides(inferenceConfiguration: InferenceConfiguration(temperature: 0.9))
    )
    _ = try await collectEvents(from: turn)
    _ = try await session.compactContext(.summarize(.init(preservedRecentTurnCount: 0)))

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
        .init(
            provider: .ofType(CompactionOverrideProvider.self),
            inferenceConfiguration: InferenceConfiguration(temperature: 0.4, maxTokens: 111)
        ),
        for: .compaction
    )
    let behavior = AgentBehavior(systemPrompt: "Test", phaseBehaviors: phaseBehaviors)
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: defaultProvider)
            .registering(CompactionOverrideProvider(base: overrideProvider)),
        behavior: behavior
    )
    let session = agent.makeSession()

    let turn = try await session.send("Hello")
    _ = try await collectEvents(from: turn)
    _ = try await session.compactContext(.summarize(.init(preservedRecentTurnCount: 0)))

    #expect(await defaultProvider.recordedCompactionConfigurations().isEmpty)
    #expect(await overrideProvider.recordedCompactionConfigurations() == [
        InferenceConfiguration(temperature: 0.4, maxTokens: 111),
    ])
    let trace = try #require(await firstManualContextCompaction(on: session))
    #expect(trace.provider == .named(String(describing: CompactionOverrideProvider.self)))
    #expect(trace.inferenceConfiguration == InferenceConfiguration(
        temperature: 0.4,
        maxTokens: 111
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
        behavior: behavior
    )
    let session = agent.makeSession()

    let turn = try await session.send("Hello")
    _ = try await collectEvents(from: turn)
    _ = try await session.compactContext(.summarize(.init(preservedRecentTurnCount: 0)))

    let recorded = await provider.recordedSummaryContexts()
    #expect(recorded.count == 1)
    #expect(recorded.first?[SentinelContextKey.self] == "sentinel-value")
    #expect(recorded.first?[AnotherSentinelContextKey.self] == "another-value")
    let trace = try #require(await firstManualContextCompaction(on: session))
    #expect(trace.inferenceContext == CustomContextSnapshot(entries: [
        .init(key: AnotherSentinelContextKey.id, valueSummary: "another-value"),
        .init(key: SentinelContextKey.id, valueSummary: "sentinel-value"),
    ]))
}

@Test func compaction_splitsOnContextWindowExceededFromSummarySession() async throws {
    let provider = SplittingCompactionProvider()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test()
    )
    let session = agent.makeSession()

    let turn = try await session.send("Hello")
    _ = try await collectEvents(from: turn)
    let result = try await session.compactContext(.summarize(.init(preservedRecentTurnCount: 0)))

    #expect(result.didCompact)
    let callCount = await provider.summarizationCallCount()
    // First call fails (both turns together), then two individual calls succeed
    #expect(callCount == 3)
}

// MARK: - Test doubles

actor CompactionConfigRecordingState {
    private(set) var compactionConfigurations: [InferenceConfiguration] = []

    func recordCompaction(_ configuration: InferenceConfiguration) {
        compactionConfigurations.append(configuration)
    }
}

struct CompactionConfigRecordingProvider: InferenceProviding {
    typealias Session = CompactionConfigRecordingSession

    let state = CompactionConfigRecordingState()

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) -> CompactionConfigRecordingSession {
        CompactionConfigRecordingSession(state: state, recordsConfiguration: toolSelection == .disabled)
    }

    func recordedCompactionConfigurations() async -> [InferenceConfiguration] {
        await state.compactionConfigurations
    }
}

actor CompactionConfigRecordingSession: InferenceSession, StructuredInferenceSession {
    private let state: CompactionConfigRecordingState
    private let recordsConfiguration: Bool
    private var messageCount = 0

    init(state: CompactionConfigRecordingState, recordsConfiguration: Bool = false) {
        self.state = state
        self.recordsConfiguration = recordsConfiguration
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        if recordsConfiguration {
            await state.recordCompaction(parameters.configuration)
        }
        messageCount += 1
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        continuation.yield(.result("ok \(messageCount)", .endTurn))
        continuation.finish()
        return stream
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        throw .generationFailed(InferenceError.invalidResponse("not supported"))
    }

    func contextUsage() async throws -> ContextUsage {
        ContextUsage(contextTokens: 90, contextSize: 100)
    }
}

extension CompactionConfigRecordingSession: ContextCompactableSession {
    func compactionEntries() -> [RenderedSessionEntry] {
        [RenderedSessionEntry(isTurnStart: true, rendered: "user: hello")]
    }

    func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int
    ) async throws -> ContextCompactionResult {
        .compacted(.init(
            usageBefore: ContextUsage(contextTokens: 90, contextSize: 100),
            usageAfter: ContextUsage(contextTokens: 10, contextSize: 100)
        ))
    }
}

// MARK: - InferenceContext forwarding doubles

private actor ContextRecordingState {
    private(set) var summaryContexts: [InferenceContext] = []

    func record(_ context: InferenceContext) {
        summaryContexts.append(context)
    }
}

private struct ContextRecordingProvider: InferenceProviding {
    typealias Session = ContextRecordingSession

    let state = ContextRecordingState()

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) -> ContextRecordingSession {
        ContextRecordingSession(
            state: state,
            isSummarySession: toolSelection == .disabled,
            inferenceContext: inferenceContext
        )
    }

    func recordedSummaryContexts() async -> [InferenceContext] {
        await state.summaryContexts
    }
}

private struct CompactionOverrideProvider: InferenceProviding {
    typealias Session = CompactionConfigRecordingSession

    let base: CompactionConfigRecordingProvider

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) -> CompactionConfigRecordingSession {
        base.makeSession(
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            inferenceContext: inferenceContext
        )
    }
}

private actor ContextRecordingSession: InferenceSession, StructuredInferenceSession {
    private let state: ContextRecordingState
    private let isSummarySession: Bool
    private let inferenceContext: InferenceContext

    init(state: ContextRecordingState, isSummarySession: Bool, inferenceContext: InferenceContext) {
        self.state = state
        self.isSummarySession = isSummarySession
        self.inferenceContext = inferenceContext
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        if isSummarySession {
            await state.record(inferenceContext)
        }
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        continuation.yield(.result("ok", .endTurn))
        continuation.finish()
        return stream
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        throw .generationFailed(InferenceError.invalidResponse("not supported"))
    }

    func contextUsage() async throws -> ContextUsage {
        ContextUsage(contextTokens: 90, contextSize: 100)
    }
}

extension ContextRecordingSession: ContextCompactableSession {
    func compactionEntries() -> [RenderedSessionEntry] {
        [RenderedSessionEntry(isTurnStart: true, rendered: "user: hello")]
    }

    func applyCompaction(summary: String?, preservedRecentTurnCount: Int) async throws -> ContextCompactionResult {
        .compacted(.init(
            usageBefore: ContextUsage(contextTokens: 90, contextSize: 100),
            usageAfter: ContextUsage(contextTokens: 10, contextSize: 100)
        ))
    }
}

// MARK: - contextWindowExceeded splitting doubles

private actor SplittingCompactionState {
    private(set) var callCount = 0

    func incrementAndReturn() -> Int {
        callCount += 1
        return callCount
    }
}

private struct SplittingCompactionProvider: InferenceProviding {
    typealias Session = SplittingCompactionSession

    let state = SplittingCompactionState()

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) -> SplittingCompactionSession {
        SplittingCompactionSession(state: state, isSummarySession: toolSelection == .disabled)
    }

    func summarizationCallCount() async -> Int {
        await state.callCount
    }
}

private actor SplittingCompactionSession: InferenceSession, StructuredInferenceSession {
    private let state: SplittingCompactionState
    private let isSummarySession: Bool

    init(state: SplittingCompactionState, isSummarySession: Bool) {
        self.state = state
        self.isSummarySession = isSummarySession
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        if isSummarySession {
            let call = await state.incrementAndReturn()
            if call == 1 {
                throw InferenceError.contextWindowExceeded(.init(message: "too large for single batch"))
            }
        }
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        continuation.yield(.result("summary", .endTurn))
        continuation.finish()
        return stream
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        throw .generationFailed(InferenceError.invalidResponse("not supported"))
    }

    func contextUsage() async throws -> ContextUsage {
        ContextUsage(contextTokens: 90, contextSize: 100)
    }
}

extension SplittingCompactionSession: ContextCompactableSession {
    func compactionEntries() -> [RenderedSessionEntry] {
        [
            RenderedSessionEntry(isTurnStart: true, rendered: "Turn A"),
            RenderedSessionEntry(isTurnStart: true, rendered: "Turn B"),
        ]
    }

    func applyCompaction(summary: String?, preservedRecentTurnCount: Int) async throws -> ContextCompactionResult {
        .compacted(.init(
            usageBefore: ContextUsage(contextTokens: 90, contextSize: 100),
            usageAfter: ContextUsage(contextTokens: 10, contextSize: 100)
        ))
    }
}
