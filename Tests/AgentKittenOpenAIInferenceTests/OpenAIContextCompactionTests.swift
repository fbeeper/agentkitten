// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenCore
@testable import AgentKittenOpenAIInference
import Testing

@Suite("OpenAI context compaction")
struct OpenAIContextCompactionTests {
    @Test("Renders each role with its configured label")
    func rendersHistoryWithRoleLabels() async {
        let client = MockOpenAIHTTPClient(responses: [])
        let session = makeOpenAITestSession(
            client: client,
            initialHistory: [
                OpenAIMessage.system("You are terse."),
                OpenAIMessage.user("Hello"),
                OpenAIMessage.assistant(text: "Hi", toolCalls: nil),
            ],
        )

        let entries = await session.compactionEntries()

        #expect(entries.map(\.rendered) == [
            "System: You are terse.",
            "User: Hello",
            "Assistant: Hi",
        ])
        // Only user messages mark turn starts.
        #expect(entries.map(\.isTurnStart) == [false, true, false])
    }

    @Test("Replaces older turns with a summary, preserving recent turns")
    func appliesCompactionWithSummary() async throws {
        // Two usage responses: one probe for usageBefore, one for usageAfter.
        let client = MockOpenAIHTTPClient(responses: [[.usage(100)], [.usage(50)]])
        let session = makeOpenAITestSession(
            client: client,
            defaultModel: "gpt-4o",
            initialHistory: [
                OpenAIMessage.user("First question"),
                OpenAIMessage.assistant(text: "First answer", toolCalls: nil),
                OpenAIMessage.user("Second question"),
                OpenAIMessage.assistant(text: "Second answer", toolCalls: nil),
            ],
        )

        let result = try await session.applyCompaction(summary: "Earlier: greetings.", preservedRecentTurnCount: 1)
        guard case .compacted = result else {
            Issue.record("Expected a compacted result.")
            return
        }

        let entries = await session.compactionEntries()
        // Summary user/assistant pair, then the single preserved recent turn.
        #expect(entries.map(\.rendered) == [
            "User: [Conversation summary]",
            "Assistant: Earlier: greetings.",
            "User: Second question",
            "Assistant: Second answer",
        ])
    }

    @Test("Reuses context size after applying compaction")
    func appliesCompactionWithSingleContextSizeLookup() async throws {
        let client = SequencedModelInfoOpenAIHTTPClient(results: [
            .success(nil),
            .failure(InferenceError.authenticationFailed(AuthenticationFailureInfo(
                provider: "OpenAI",
                message: "auth failed",
                statusCode: 401,
            ))),
        ])
        let session = OpenAIInferenceSession(
            client: client,
            defaultModel: "test-model",
            systemPrompt: nil,
            toolRuntime: testOpenAIToolRuntime(),
            initialHistory: [
                OpenAIMessage.user("First question"),
                OpenAIMessage.assistant(text: "First answer", toolCalls: nil),
                OpenAIMessage.user("Second question"),
                OpenAIMessage.assistant(text: "Second answer", toolCalls: nil),
            ],
        )

        let result = try await session.applyCompaction(summary: nil, preservedRecentTurnCount: 1)

        #expect(result.didCompact)
        #expect(await client.modelInfoRequestCount == 1)
        let entries = await session.compactionEntries()
        #expect(entries.map(\.rendered) == [
            "User: Second question",
            "Assistant: Second answer",
        ])
    }

    @Test("Skips compaction when history is empty")
    func skipsEmptyHistory() async throws {
        let client = MockOpenAIHTTPClient(responses: [])
        let session = makeOpenAITestSession(client: client)
        let result = try await session.applyCompaction(summary: "x", preservedRecentTurnCount: 1)
        guard case .skipped = result else {
            Issue.record("Expected compaction to be skipped for empty history.")
            return
        }
    }
}

private actor SequencedModelInfoOpenAIHTTPClient: OpenAIHTTPStreaming {
    private var results: [Result<Int?, Error>]
    private(set) var modelInfoRequestCount = 0

    init(results: [Result<Int?, Error>]) {
        self.results = results
    }

    func stream(request: OpenAIRequest) async throws -> AsyncThrowingStream<OpenAISSEEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.usage(50))
            continuation.finish()
        }
    }

    func maxInputTokens(for model: String) async throws -> Int? {
        modelInfoRequestCount += 1
        let result = results.isEmpty ? .success(nil) : results.removeFirst()
        return try result.get()
    }
}
#endif
