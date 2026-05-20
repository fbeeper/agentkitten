// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Test func compaction_trimsSummaryWhitespaceBeforeApplyingSummary() async throws {
    let provider = TrailingWhitespaceSummaryProvider()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let turn = try await session.send("Hello")
    _ = try await collectEvents(from: turn)
    _ = try await session.compactContext(
        .summarize(ContextCompactionOptions.SummarizationOptions(preservedRecentTurnCount: 0)),
    )

    #expect(await provider.appliedSummaries() == ["summary"])
}

private actor TrailingWhitespaceSummaryState {
    private(set) var appliedSummaries: [String] = []

    func record(summary: String?) {
        guard let summary else {
            return
        }
        appliedSummaries.append(summary)
    }
}

private struct TrailingWhitespaceSummaryProvider: InferenceProviding {
    typealias Session = TrailingWhitespaceSummarySession

    let state = TrailingWhitespaceSummaryState()

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> TrailingWhitespaceSummarySession {
        TrailingWhitespaceSummarySession(
            state: state,
            isSummarySession: toolSelection == .disabled,
        )
    }

    func appliedSummaries() async -> [String] {
        await state.appliedSummaries
    }
}

private actor TrailingWhitespaceSummarySession: InferenceSession, StructuredInferenceSession {
    private let state: TrailingWhitespaceSummaryState
    private let isSummarySession: Bool

    init(state: TrailingWhitespaceSummaryState, isSummarySession: Bool) {
        self.state = state
        self.isSummarySession = isSummarySession
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        let text = isSummarySession ? "summary\n\n" : "ok"
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        continuation.yield(.result(text, .endTurn))
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

extension TrailingWhitespaceSummarySession: ContextCompactableSession {
    func compactionEntries() -> [RenderedSessionEntry] {
        [RenderedSessionEntry(isTurnStart: true, rendered: "user: hello")]
    }

    func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int,
    ) async throws -> ContextCompactionResult {
        _ = preservedRecentTurnCount
        await state.record(summary: summary)
        return .compacted(ContextCompactionResult.Compacted(
            usageBefore: ContextUsage(contextTokens: 90, contextSize: 100),
            usageAfter: ContextUsage(contextTokens: 10, contextSize: 100),
        ))
    }
}
