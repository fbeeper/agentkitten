// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import AgentKittenInferenceTestSupport
import Testing

/// Smoke-checks that the Anthropic session emits streams satisfying the shared
/// ``InferenceEvent`` contract, alongside the provider-specific tests. Drives a
/// real session over a mock HTTP client and pipes its raw stream through
/// ``InferenceStreamValidator``.
@Suite("Anthropic stream conformance")
struct AnthropicStreamConformanceTests {
    @Test("Text turn satisfies the inference stream contract")
    func textTurnConforms() async throws {
        let mock = MockHTTPClient(responses: [
            [.textDelta("Hello there"), .stopReason("end_turn")],
        ])
        let session = makeSession(client: mock)
        let stream = try await session.run(
            UserMessage(text: "Hi"),
            parameters: InferenceRequestParameters(toolSelection: .disabled),
        )
        let events = try await InferenceStreamValidator.validate(stream)
        guard case .result = events.last else {
            Issue.record("Expected the stream to terminate with `.result`.")
            return
        }
    }

    @Test("Tool-use turn satisfies the inference stream contract")
    func toolUseTurnConforms() async throws {
        let mock = MockHTTPClient(responses: [
            [
                .toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"),
                .stopReason("tool_use"),
            ],
            [.textDelta("Done"), .stopReason("end_turn")],
        ])
        let session = makeSession(client: mock)
        let stream = try await session.run(
            UserMessage(text: "Use a tool"),
            parameters: InferenceRequestParameters(toolStepBudget: .budget(1)),
        )
        let events = try await InferenceStreamValidator.validate(stream)
        let requested = events.contains { if case .toolCallRequested = $0 { true } else { false } }
        #expect(requested, "Expected a tool-call request in the stream.")
    }
}
#endif
