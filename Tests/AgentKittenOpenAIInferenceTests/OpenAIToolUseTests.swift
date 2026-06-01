// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenCore
@testable import AgentKittenOpenAIInference
import Testing

@Suite("OpenAI tool use")
struct OpenAIToolUseTests {
    private func collect(
        _ session: OpenAIInferenceSession,
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

    @Test("Throws when tool_calls finish reason has no assembled tool calls")
    func throwsForEmptyToolCallsFinish() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.stopReason("tool_calls")],
            [.textDelta("should not be requested"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        await #expect(throws: InferenceError.self) {
            _ = try await collect(session)
        }
        #expect(client.callCount == 1)
    }

    @Test("Emits paired tool-call events and follows up to a final answer")
    func followsUpForRealToolCall() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [
                .toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"),
                .stopReason("tool_calls"),
            ],
            [.textDelta("Done"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        let events = try await collect(session)

        #expect(client.callCount == 2)
        let requested = events.contains {
            if case .toolCallRequested(_, "missing_tool", _) = $0 { true } else { false }
        }
        let completed = events.contains {
            if case .toolCallCompleted(_, "missing_tool", _) = $0 { true } else { false }
        }
        #expect(requested)
        #expect(completed)
        let text = events.compactMap { if case .delta(let chunk) = $0 { chunk } else { nil } }.joined()
        #expect(text == "Done")
    }

    @Test("Loop halts after step budget is exhausted even if the model keeps requesting tools")
    func haltsWhenToolStepBudgetExhausted() async throws {
        // budget(1) → round 1 succeeds (budget 1→0); round 2 fails with
        // stepLimitExceeded. The session must allow one follow-up after the first
        // budget failure so the model can respond to the error result (round 3),
        // then exit even if the model keeps requesting tools. Without the fix the
        // loop drives all 4 mock requests.
        let client = MockOpenAIHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_calls")],
            [.toolCallReady(id: "call-2", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_calls")],
            [.toolCallReady(id: "call-3", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_calls")],
            [.textDelta("Done"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        _ = try await collect(
            session,
            parameters: InferenceRequestParameters(toolStepBudget: .budget(1)),
        )

        // Round 1: tool succeeds. Round 2: tool fails (budget=0). Round 3: allowed
        // as the one follow-up so the model sees the error result. Round 4 must not
        // be issued — that would mean the loop is running past budget exhaustion.
        #expect(client.callCount < 4, "Loop issued \(client.callCount) requests; expected ≤ 3 with budget(1).")
    }

    @Test("Sends tool definitions on the request and a tool result on the follow-up")
    func wiresToolsAndResultsIntoRequests() async throws {
        let registry = ToolRegistry()
        let client = MockOpenAIHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_calls")],
            [.textDelta("Done"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(registry: registry, client: client)
        _ = try await collect(session)

        // Follow-up request must carry the assistant tool_call turn + the tool result.
        let followUp = client.capturedRequests[1]
        let roles = followUp.messages.map(\.role)
        #expect(roles.contains(.assistant))
        #expect(roles.contains(.tool))
    }
}
#endif
