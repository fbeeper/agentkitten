// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
@testable import AgentKittenInference
import Synchronization
import Testing

private final class ModelInfoHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let maxInputTokensValue: Int?

    init(maxInputTokensValue: Int?) {
        self.maxInputTokensValue = maxInputTokensValue
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func countTokens(request: AnthropicCountTokensRequest) async throws -> Int {
        0
    }

    func maxInputTokens(for model: String) async throws -> Int? {
        maxInputTokensValue
    }
}

private struct FailingModelInfoHTTPClient: AnthropicHTTPStreaming {
    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func countTokens(request: AnthropicCountTokensRequest) async throws -> Int {
        0
    }

    func maxInputTokens(for model: String) async throws -> Int? {
        throw InferenceError.invalidResponse("lookup failed")
    }
}

private final class CountingModelInfoHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let callCountState = Mutex(0)

    var callCount: Int {
        callCountState.withLock { $0 }
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func countTokens(request: AnthropicCountTokensRequest) async throws -> Int {
        0
    }

    func maxInputTokens(for model: String) async throws -> Int? {
        callCountState.withLock { $0 += 1 }
        return 123_456
    }
}

@Test func session_accumulatesCachedContextTokensAcrossToolUseCycles() async throws {
    let mock = MockHTTPClient(responses: [
        [.usage(300), .stopReason("tool_use")],
        [.usage(150), .textDelta("Done"), .stopReason("end_turn")],
    ])
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        clientFactory: { _ in mock },
    )

    for try await _ in try await session.run(
        UserMessage(text: "Hi"),
        parameters: InferenceRequestParameters(),
    ) {}

    let usage = try await session.contextUsage()
    // Each request re-sends the full history, so `total` from the last request
    // already covers the entire context. The final value must be 150, not 300+150.
    #expect(usage.contextTokens == 150, "Expected cached token count to reflect the last request's full context total")
}

@Test func providerCompactedRebuild_returnsSkippedWhenCountingFails() async throws {
    struct FailingCountHTTPClient: AnthropicHTTPStreaming {
        func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        func countTokens(request: AnthropicCountTokensRequest) async throws -> Int {
            throw InferenceError.invalidResponse("count failed")
        }
    }

    let history = [
        AnthropicMessage(role: .user, content: [.text("Original request.")]),
        AnthropicMessage(role: .assistant, content: [.text("Original answer.")]),
    ]
    let provider = AnthropicInferenceProvider(
        credentials: MockAPIKeyProvider("test-key"),
        model: "test-model",
    )
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        initialHistory: history,
        clientFactory: { _ in FailingCountHTTPClient() },
    )

    let result = await ContextCompactor().compact(
        session,
        options: .truncate(ContextCompactionOptions.TruncationOptions(preservedRecentTurnCount: 1)),
        summaryGenerator: makeSummaryGenerator(
            client: MinimalCapturingHTTPClient(),
        ),
    )
    let rebuilt = try await provider.makeSession(
        continuing: session,
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        toolSelection: .all,
        inferenceContext: InferenceContext(),
    )

    #expect(result.isFailedSkip)
    let rebuiltHistory = await rebuilt.captureHistory()
    #expect(rebuiltHistory.map(\.role.rawValue) == ["user", "assistant"])
    let rebuiltText = rebuiltHistory.flatMap(\.content).compactMap {
        if case .text(let text) = $0 { text } else { nil }
    }.joined(separator: " ")
    #expect(rebuiltText.contains("Original request."))
    #expect(rebuiltText.contains("Original answer."))
}

@Test func providerSession_contextUsageUsesKnownModelWindow() async throws {
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "claude-sonnet-4-20250514",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        clientFactory: { _ in ModelInfoHTTPClient(maxInputTokensValue: 1_048_576) },
    )

    let usage = try await session.contextUsage()
    #expect(usage.contextSize == 1_048_576)
}

@Test func providerSession_contextUsageFallsBackToStandardModelWindowWhenLookupFails() async throws {
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "claude-sonnet-4-20250514",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        clientFactory: { _ in FailingModelInfoHTTPClient() },
    )

    let usage = try await session.contextUsage()
    #expect(usage.contextSize == 200_000)
}

@Test func providerSession_contextUsageCachesResolvedModelWindow() async throws {
    let client = CountingModelInfoHTTPClient()
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "claude-sonnet-4-20250514",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        clientFactory: { _ in client },
    )

    let firstUsage = try await session.contextUsage()
    let secondUsage = try await session.contextUsage()

    #expect(firstUsage.contextSize == 123_456)
    #expect(secondUsage.contextSize == 123_456)
    #expect(client.callCount == 1)
}

@Test func providerContinuingSession_resetsToDefaultModelAfterTurnOverride() async throws {
    let provider = AnthropicInferenceProvider(
        credentials: MockAPIKeyProvider("test-key"),
        model: "claude-sonnet-4-20250514",
    )
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "claude-sonnet-4-20250514",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        clientFactory: { _ in ModelInfoHTTPClient(maxInputTokensValue: 1_048_576) },
    )
    let parameters = InferenceRequestParameters(
        inferenceContext: {
            var context = InferenceContext()
            context[AnthropicModelKey.self] = "claude-opus-4-1"
            return context
        }(),
    )
    _ = await session.buildRequest(
        from: [AnthropicMessage(role: .user, content: [.text("Hi")])],
        parameters: parameters,
    )

    let rebuilt = try await provider.makeSession(
        continuing: session,
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        toolSelection: .all,
        inferenceContext: InferenceContext(),
    )

    let usage = try await rebuilt.contextUsage()
    #expect(usage.contextSize == 200_000)
}

@Test func anthropicCompactedHistory_summarizesOlderTurnsAndPreservesRecent() async throws {
    let client = MinimalCapturingHTTPClient(responseText: "Summary of old Anthropic history.")
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "claude-sonnet-4-5",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        initialHistory: [
            AnthropicMessage(role: .user, content: [.text("Old request one.")]),
            AnthropicMessage(role: .assistant, content: [.text("Old answer one.")]),
            AnthropicMessage(role: .user, content: [.text("Recent request one.")]),
            AnthropicMessage(role: .assistant, content: [.text("Recent answer one.")]),
            AnthropicMessage(role: .user, content: [.text("Recent request two.")]),
            AnthropicMessage(role: .assistant, content: [.text("Recent answer two.")]),
        ],
        clientFactory: { _ in client },
    )

    let result = await ContextCompactor().compact(
        session,
        options: .summarize(
            ContextCompactionOptions.SummarizationOptions(preservedRecentTurnCount: 2),
        ),
        summaryGenerator: makeSummaryGenerator(client: client),
    )
    #expect(result.didCompact)

    let request = try #require(client.capturedRequest)
    let capturedPrompt = try #require(
        request.messages.compactMap { msg -> String? in
            msg.content.compactMap { if case .text(let txt) = $0 { txt } else { nil } }.first
        }.first,
    )
    #expect(capturedPrompt.contains("Old request one."))
    #expect(capturedPrompt.contains("Old answer one."))
    #expect(!capturedPrompt.contains("Recent request two."))

    let history = await session.captureHistory()
    #expect(history.count == 6)
    let allText = history.flatMap(\.content).compactMap {
        if case .text(let text) = $0 { text } else { nil }
    }.joined(separator: " ")
    #expect(allText.contains("[Conversation summary]"))
    #expect(allText.contains("Summary of old Anthropic history."))
    #expect(allText.contains("Recent request one."))
    #expect(allText.contains("Recent request two."))
    #expect(!allText.contains("Old answer one."))
}

@Test func anthropicCompactedHistory_truncatesOldMessages() async {
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        initialHistory: [
            AnthropicMessage(role: .user, content: [.text("Old request.")]),
            AnthropicMessage(role: .assistant, content: [.text("Old answer.")]),
            AnthropicMessage(role: .user, content: [.text("Recent request.")]),
            AnthropicMessage(role: .assistant, content: [.text("Recent answer.")]),
        ],
        clientFactory: { _ in MinimalCapturingHTTPClient() },
    )

    let result = await ContextCompactor().compact(
        session,
        options: .truncate(
            ContextCompactionOptions.TruncationOptions(preservedRecentTurnCount: 1),
        ),
        summaryGenerator: makeSummaryGenerator(
            client: MinimalCapturingHTTPClient(),
        ),
    )
    #expect(result.didCompact)

    let history = await session.captureHistory()
    let allText = history.flatMap(\.content).compactMap {
        if case .text(let text) = $0 { text } else { nil }
    }.joined(separator: " ")

    #expect(history.count == 2)
    #expect(allText.contains("Recent request."))
    #expect(allText.contains("Recent answer."))
    #expect(!allText.contains("Old request."))
    #expect(!allText.contains("Old answer."))
}

@Test func anthropicSummarizer_customPromptReplacesDefaultPreamble() async throws {
    let customPrompt = "You are a medical summarizer.\n\n%@\n\nPreserve clinical facts only."
    let client = MinimalCapturingHTTPClient()
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "claude-sonnet-4-5",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        initialHistory: [
            AnthropicMessage(role: .user, content: [.text("Old request.")]),
            AnthropicMessage(role: .assistant, content: [.text("Old answer.")]),
            AnthropicMessage(role: .user, content: [.text("Recent request.")]),
            AnthropicMessage(role: .assistant, content: [.text("Recent answer.")]),
        ],
        clientFactory: { _ in client },
    )

    _ = await ContextCompactor().compact(session,
                                         options: .summarize(ContextCompactionOptions.SummarizationOptions(
                                             preservedRecentTurnCount: 1,
                                             summaryInstructionFormat: customPrompt,
                                         )),
                                         summaryGenerator: makeSummaryGenerator(client: client))

    let request = try #require(client.capturedRequest)
    let captured = try #require(
        request.messages.compactMap { msg -> String? in
            msg.content.compactMap { if case .text(let txt) = $0 { txt } else { nil } }.first
        }.first,
    )
    #expect(captured.contains("You are a medical summarizer."))
    #expect(captured.contains("Old request."))
    #expect(captured.contains("Preserve clinical facts only."))
    #expect(!captured.contains("Summarize the following"))
    #expect(!captured.contains("Preserve durable facts"))
}

@Test func anthropicSummarizer_standardPromptPlacesHistoryWhereFormatted() async throws {
    let client = MinimalCapturingHTTPClient()
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "claude-sonnet-4-5",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        initialHistory: [
            AnthropicMessage(role: .user, content: [.text("Old request.")]),
            AnthropicMessage(role: .assistant, content: [.text("Old answer.")]),
            AnthropicMessage(role: .user, content: [.text("Recent request.")]),
            AnthropicMessage(role: .assistant, content: [.text("Recent answer.")]),
        ],
        clientFactory: { _ in client },
    )

    _ = await ContextCompactor().compact(
        session,
        options: .summarize(
            ContextCompactionOptions.SummarizationOptions(
                preservedRecentTurnCount: 1,
                summaryInstructionFormat: "Prefix\n%@\nSuffix",
            ),
        ),
        summaryGenerator: makeSummaryGenerator(client: client),
    )

    let request = try #require(client.capturedRequest)
    let captured = try #require(
        request.messages.compactMap { msg -> String? in
            msg.content.compactMap { if case .text(let txt) = $0 { txt } else { nil } }.first
        }.first,
    )
    #expect(captured.hasPrefix("Prefix"))
    #expect(captured.contains("History:"))
    #expect(captured.contains("Old request."))
    #expect(captured.hasSuffix("Suffix"))
}

extension ContextCompactionResult {
    fileprivate var isFailedSkip: Bool {
        switch self {
        case .skipped(.failed), .skipped(.inferenceError):
            true
        default:
            false
        }
    }
}
