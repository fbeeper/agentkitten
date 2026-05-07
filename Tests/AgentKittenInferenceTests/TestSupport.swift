// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
import Synchronization
@testable import AgentKittenCore
@testable import AgentKittenInference

func testToolRuntime(
    registry: ToolRegistry = ToolRegistry(),
    executionPolicy: some ToolExecutionPolicy = AutoApprovePolicy()
) -> ToolRuntime {
    ToolRuntime(
        configuration: ToolDefinition(
            tools: registry.all,
            executionPolicy: executionPolicy
        )
    )
}

func singleTextContent(in content: [ToolResultContent]) -> String? {
    guard content.count == 1, case .text(let text) = content[0] else {
        return nil
    }
    return text
}

func nextApprovalCall(
    from iterator: inout TurnEventStream<AssistantMessage>.AsyncIterator
) async throws -> PendingToolCall {
    while let event = try await iterator.next() {
        if case .toolApprovalRequired(let call) = event.kind {
            return call
        }
    }

    let missingCall: PendingToolCall? = nil
    return try #require(missingCall, "Expected toolApprovalRequired before stream completion")
}

extension AnthropicHTTPStreaming {
    func countTokens(request: AnthropicCountTokensRequest) async throws -> Int { 0 }
}

/// Mirrors `AnyInferenceProvider.generateIsolated` for tests: creates an
/// ephemeral session backed by the given client and streams the prompt through it.
func makeSummaryGenerator(client: MinimalCapturingHTTPClient) -> @Sendable (String) async throws -> String {
    { @Sendable prompt in
        let ephemeral = AnthropicInferenceSession(
            credentials: MockAPIKeyProvider("test-key"),
            defaultModel: "test-model",
            systemPrompt: nil,
            toolRuntime: testToolRuntime(),
            clientFactory: { _ in client }
        )
        let stream = try await ephemeral.run(
            UserMessage(text: prompt),
            parameters: InferenceRequestParameters(toolSelection: .disabled)
        )
        for try await event in stream {
            if case .result(let text, _) = event {
                return text
            }
        }
        throw InferenceError.invalidResponse("Summarization produced no result.")
    }
}

/// Captures the most recent request and returns a configurable success response.
final class MinimalCapturingHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let capturedRequestState = Mutex<AnthropicRequest?>(nil)
    private let responseText: String

    init(responseText: String = "ok") {
        self.responseText = responseText
    }

    var capturedRequest: AnthropicRequest? {
        capturedRequestState.withLock { $0 }
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        capturedRequestState.withLock { $0 = request }
        return AsyncThrowingStream { [responseText] continuation in
            continuation.yield(.textDelta(responseText))
            continuation.yield(.stopReason("end_turn"))
            continuation.finish()
        }
    }
}
