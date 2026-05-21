// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore

// MARK: - InferenceConfiguration recording doubles

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
        inferenceContext: InferenceContext,
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
        parameters: InferenceRequestParameters,
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
        preservedRecentTurnCount: Int,
    ) async throws -> ContextCompactionResult {
        .compacted(ContextCompactionResult.Compacted(
            usageBefore: ContextUsage(contextTokens: 90, contextSize: 100),
            usageAfter: ContextUsage(contextTokens: 10, contextSize: 100),
        ))
    }
}

// MARK: - InferenceContext forwarding doubles

actor ContextRecordingState {
    private(set) var summaryContexts: [InferenceContext] = []

    func record(_ context: InferenceContext) {
        summaryContexts.append(context)
    }
}

struct ContextRecordingProvider: InferenceProviding {
    typealias Session = ContextRecordingSession

    let state = ContextRecordingState()

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> ContextRecordingSession {
        ContextRecordingSession(
            state: state,
            isSummarySession: toolSelection == .disabled,
            inferenceContext: inferenceContext,
        )
    }

    func recordedSummaryContexts() async -> [InferenceContext] {
        await state.summaryContexts
    }
}

struct CompactionOverrideProvider: InferenceProviding {
    typealias Session = CompactionConfigRecordingSession

    let base: CompactionConfigRecordingProvider

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> CompactionConfigRecordingSession {
        base.makeSession(
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            inferenceContext: inferenceContext,
        )
    }
}

actor ContextRecordingSession: InferenceSession, StructuredInferenceSession {
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
        parameters: InferenceRequestParameters,
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
        .compacted(ContextCompactionResult.Compacted(
            usageBefore: ContextUsage(contextTokens: 90, contextSize: 100),
            usageAfter: ContextUsage(contextTokens: 10, contextSize: 100),
        ))
    }
}

// MARK: - contextWindowExceeded splitting doubles

actor SplittingCompactionState {
    private(set) var callCount = 0

    func incrementAndReturn() -> Int {
        callCount += 1
        return callCount
    }
}

struct SplittingCompactionProvider: InferenceProviding {
    typealias Session = SplittingCompactionSession

    let state = SplittingCompactionState()

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> SplittingCompactionSession {
        SplittingCompactionSession(state: state, isSummarySession: toolSelection == .disabled)
    }

    func summarizationCallCount() async -> Int {
        await state.callCount
    }
}

actor SplittingCompactionSession: InferenceSession, StructuredInferenceSession {
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
                throw InferenceError.contextWindowExceeded(
                    ContextWindowExceededInfo(message: "too large for single batch"),
                )
            }
        }
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        continuation.yield(.result("summary", .endTurn))
        continuation.finish()
        return stream
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
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
        .compacted(ContextCompactionResult.Compacted(
            usageBefore: ContextUsage(contextTokens: 90, contextSize: 100),
            usageAfter: ContextUsage(contextTokens: 10, contextSize: 100),
        ))
    }
}
