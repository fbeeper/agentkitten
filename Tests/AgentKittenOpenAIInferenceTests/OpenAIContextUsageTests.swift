// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenCore
@testable import AgentKittenOpenAIInference
import Testing

@Suite("OpenAI context usage")
struct OpenAIContextUsageTests {
    private func runTurn(_ session: OpenAIInferenceSession) async throws {
        for try await _ in try await session.run(
            UserMessage(text: "Hi"),
            parameters: InferenceRequestParameters(toolSelection: .disabled),
        ) {}
    }

    @Test("Reports cached usage tokens and nil context size when /models returns no data")
    func reportsUsageWithNilContextSize() async throws {
        // The mock returns no metadata, so contextSize is nil — callers must handle it.
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta("hi"), .stopReason("stop"), .usage(321)],
        ])
        let session = makeOpenAITestSession(client: client, defaultModel: "gpt-4o")
        try await runTurn(session)

        let usage = try await session.contextUsage()
        #expect(usage.contextTokens == 321)
        #expect(usage.contextSize == nil)
    }

    @Test("Resolves an unknown model's context window from /models metadata")
    func resolvesContextSizeFromModelMetadata() async throws {
        let client = MockOpenAIHTTPClient(
            responses: [[.textDelta("hi"), .stopReason("stop"), .usage(10)]],
            maxInputTokensByModel: ["mystery-model": 32000],
        )
        let session = makeOpenAITestSession(client: client, defaultModel: "mystery-model")
        try await runTurn(session)

        let usage = try await session.contextUsage()
        #expect(usage.contextSize == 32000)
        #expect(client.capturedModelInfoRequests == ["mystery-model"])
    }

    @Test("Caches the resolved context size across calls")
    func cachesResolvedContextSize() async throws {
        let client = MockOpenAIHTTPClient(
            responses: [[.textDelta("hi"), .stopReason("stop"), .usage(10)]],
            maxInputTokensByModel: ["mystery-model": 32000],
        )
        let session = makeOpenAITestSession(client: client, defaultModel: "mystery-model")
        try await runTurn(session)

        _ = try await session.contextUsage()
        _ = try await session.contextUsage()
        #expect(client.capturedModelInfoRequests == ["mystery-model"], "Expected a single metadata lookup.")
    }

    @Test("Applies the per-turn model override to the request")
    func appliesModelOverride() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta("hi"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client, defaultModel: "gpt-4o")
        var context = InferenceContext.empty
        context[OpenAIModelKey.self] = "gpt-4o-mini"
        for try await _ in try await session.run(
            UserMessage(text: "Hi"),
            parameters: InferenceRequestParameters(toolSelection: .disabled, inferenceContext: context),
        ) {}

        #expect(client.capturedRequests[0].model == "gpt-4o-mini")
    }
}
#endif
