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
        // budget(1): round 1 tool succeeds (1→0); round 2 budget=0 so tool fails
        // (stepLimitExceeded); round 3 is the follow-up where the model can respond
        // to the errors. A stubborn model that still calls tools in round 3 gets cut
        // off there. Round 4 must never be issued.
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
        #expect(
            client.callCount == 3,
            "Expected exactly 3 requests: round 1 (tool ok), round 2 (tool fails), round 3 (follow-up, then stop).",
        )
    }

    @Test("Model can respond to stepLimitExceeded errors when budget is exhausted")
    func modelRespondsToStepLimitExceededErrors() async throws {
        // budget(1): round 1 tool call counts against budget; round 2 tool fails;
        // round 3 is the follow-up where the model replies with text.
        let client = MockOpenAIHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_calls")],
            [.toolCallReady(id: "call-2", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_calls")],
            [.textDelta("I hit the step limit."), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        let events = try await collect(
            session,
            parameters: InferenceRequestParameters(toolStepBudget: .budget(1)),
        )
        #expect(client.callCount == 3, "Follow-up round must fire so the model can respond to errors.")
        let text = events.compactMap { if case .delta(let chunk) = $0 { chunk } else { nil } }.joined()
        #expect(
            text == "I hit the step limit.",
            "Result text must come from the model's error-acknowledgement response.",
        )
    }

    @Test("disabled budget: model receives stepLimitExceeded errors and can respond before loop stops")
    func disabledBudgetAllowsFollowUpAfterErrors() async throws {
        // toolStepBudget: .disabled means tool execution is disabled (zero capacity).
        // Round 1: model calls tools → all fail with stepLimitExceeded.
        // Round 2: follow-up so the model can respond to the errors (must not be skipped).
        let client = MockOpenAIHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_calls")],
            [.textDelta("Tools are disabled."), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        let events = try await collect(
            session,
            parameters: InferenceRequestParameters(toolStepBudget: .disabled),
        )
        #expect(
            client.callCount == 2,
            "Follow-up round must fire so the model can respond to stepLimitExceeded errors.",
        )
        let text = events.compactMap { if case .delta(let chunk) = $0 { chunk } else { nil } }.joined()
        #expect(text == "Tools are disabled.", "Result text must come from the model's follow-up response.")
    }

    @Test("Discards tool calls and surfaces maxTokens when finish reason is length")
    func discardsToolCallsOnLengthFinish() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("length")],
        ])
        let session = makeOpenAITestSession(client: client)
        let events = try await collect(session)

        #expect(client.callCount == 1, "No follow-up request should be issued after length finish.")
        #expect(!events.contains(where: { if case .toolCallRequested = $0 { true } else { false } }),
                "toolCallRequested must not appear when tool calls are discarded due to length finish.")
        let finishReason = events.compactMap {
            if case .result(_, let reason) = $0 { reason } else { nil }
        }.first
        #expect(finishReason == .maxTokens)
    }

    @Test("Length-finished tool-only turn does not reuse prior assistant text")
    func lengthFinishedToolOnlyTurnDoesNotReusePriorAssistantText() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta("Old answer"), .stopReason("stop")],
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("length")],
        ])
        let session = makeOpenAITestSession(client: client)

        _ = try await collect(session, "First")
        let events = try await collect(session, "Second")
        let result = events.compactMap {
            if case .result(let output, let reason) = $0 {
                (output, reason)
            } else {
                nil
            }
        }.first

        #expect(result?.0 == "")
        #expect(result?.1 == .maxTokens)
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
