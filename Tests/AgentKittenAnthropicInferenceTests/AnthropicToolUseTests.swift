// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import Testing

@Suite("Anthropic tool use")
struct AnthropicToolUseTests {
    private func collect(
        _ session: AnthropicInferenceSession,
        _ message: String = "Hi",
        parameters: InferenceRequestParameters = InferenceRequestParameters(),
    ) async throws -> [InferenceEvent<String>] {
        var events: [InferenceEvent<String>] = []
        for try await event in try await session.run(
            UserMessage(text: message),
            parameters: parameters,
        ) {
            events.append(event)
        }
        return events
    }

    @Test("Loop halts after step budget is exhausted even if the model keeps requesting tools")
    func haltsWhenToolStepBudgetExhausted() async throws {
        // budget(1) → round 1 succeeds (budget 1→0); round 2 fails with
        // stepLimitExceeded. The session must allow one follow-up after the first
        // budget failure so the model can respond to the error result (round 3),
        // then exit even if the model keeps requesting tools. Without the fix the
        // loop drives all 4 mock requests.
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_use")],
            [.toolCallReady(id: "call-2", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_use")],
            [.toolCallReady(id: "call-3", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_use")],
            [.textDelta("Done"), .stopReason("end_turn")],
        ])
        let session = makeSession(clientFactory: { _ in mock })
        _ = try await collect(
            session,
            parameters: InferenceRequestParameters(toolStepBudget: .budget(1)),
        )

        // Round 1: tool succeeds. Round 2: tool fails (budget=0). Round 3: allowed
        // as the one follow-up so the model sees the error result. Round 4 must not
        // be issued — that would mean the loop is running past budget exhaustion.
        #expect(mock.callCount < 4, "Loop issued \(mock.callCount) requests; expected ≤ 3 with budget(1).")
    }
}
#endif
