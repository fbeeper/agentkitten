// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
@testable import AgentKittenInferenceTestSupport
import Testing

/// Exercises `verifyProviderStreamContracts` against the in-tree
/// ``MockInferenceProvider`` — the reference conformer that every real
/// provider's stream is expected to behave like.
@Suite("Mock provider stream conformance")
struct MockProviderConformanceTests {
    private func toolRuntime() -> ToolRuntime {
        ToolRuntime(toolDefinition: .noTools, toolBehavior: ToolBehavior())
    }

    @Test("Text-only turn satisfies the stream contract")
    func textTurnConforms() async throws {
        let provider = MockInferenceProvider(responses: ["Hello there friend"])
        let events = try await verifyProviderStreamContracts(
            provider,
            toolRuntime: toolRuntime(),
            toolSelection: .disabled,
        )
        guard case .result = events.last else {
            Issue.record("Expected the stream to terminate with `.result`.")
            return
        }
    }

    @Test("Tool-call turn satisfies the stream contract")
    func toolCallTurnConforms() async throws {
        let provider = MockInferenceProvider(
            mockResponses: [
                .toolCall(name: "lookup", argumentsJSON: "{}", thenRespond: "All done"),
            ],
        )
        let events = try await verifyProviderStreamContracts(
            provider,
            toolRuntime: toolRuntime(),
            toolSelection: .all,
        )
        let requested = events.contains { if case .toolCallRequested = $0 { true } else { false } }
        let completed = events.contains { if case .toolCallCompleted = $0 { true } else { false } }
        #expect(requested)
        #expect(completed)
    }
}

@discardableResult
private func verifyProviderStreamContracts(
    _ provider: some InferenceProviding,
    systemPrompt: String? = nil,
    toolRuntime: ToolRuntime,
    toolSelection: ToolSelection = .all,
    inferenceContext: InferenceContext = .empty,
    message: UserMessage = UserMessage(text: "Say hello."),
    parameters: InferenceRequestParameters? = nil,
) async throws -> [InferenceEvent<String>] {
    let session = provider.makeSession(
        systemPrompt: systemPrompt,
        toolRuntime: toolRuntime,
        toolSelection: toolSelection,
        inferenceContext: inferenceContext,
    )
    let resolvedParameters = parameters ?? InferenceRequestParameters(toolSelection: toolSelection)
    let stream = try await session.run(message, parameters: resolvedParameters)
    return try await InferenceStreamValidator.validate(stream)
}
