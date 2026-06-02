// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import AgentKittenInferenceSupport
import Synchronization
import Testing

/// Records whether its `before` hook fired. Thread-safe via internal `Mutex`.
private final class HookSpy: ToolHook, @unchecked Sendable {
    var name: String {
        "spy"
    }

    var phases: Set<ToolHookPhase> {
        [.before]
    }

    private let _fired = Mutex(false)
    var fired: Bool {
        _fired.withLock { $0 }
    }

    func beforeExecute(_ call: PendingToolCall, context: ToolExecutionContext) async throws -> PendingToolCall {
        _fired.withLock { $0 = true }
        return call
    }
}

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
        // budget(1): round 1 tool succeeds (1→0); round 2 budget=0 so tool fails
        // (stepLimitExceeded); round 3 is the follow-up where the model can respond
        // to the errors. A stubborn model that still calls tools in round 3 gets cut
        // off there. Round 4 must never be issued.
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
        #expect(
            mock.callCount == 3,
            "Expected exactly 3 requests: round 1 (tool ok), round 2 (tool fails), round 3 (follow-up, then stop).",
        )
    }

    @Test("Model can respond to stepLimitExceeded errors when budget is exhausted")
    func modelRespondsToStepLimitExceededErrors() async throws {
        // budget(1): round 1 tool call (counts against budget); round 2 tool fails
        // (stepLimitExceeded); round 3 is the follow-up where the model replies
        // with text — that text must appear in the result.
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_use")],
            [.toolCallReady(id: "call-2", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_use")],
            [.textDelta("I hit the step limit."), .stopReason("end_turn")],
        ])
        let session = makeSession(clientFactory: { _ in mock })
        let events = try await collect(
            session,
            parameters: InferenceRequestParameters(toolStepBudget: .budget(1)),
        )
        #expect(mock.callCount == 3, "Follow-up round must fire so the model can respond to errors.")
        let text = events.compactMap {
            if case .result(let output, _) = $0 {
                output
            } else {
                nil
            }
        }.first
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
        // Without the fix, the loop broke after round 1, orphaning the error results.
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_use")],
            [.textDelta("Tools are disabled."), .stopReason("end_turn")],
        ])
        let session = makeSession(clientFactory: { _ in mock })
        let events = try await collect(
            session,
            parameters: InferenceRequestParameters(toolStepBudget: .disabled),
        )
        #expect(mock.callCount == 2, "Follow-up round must fire so the model can respond to stepLimitExceeded errors.")
        let text = events.compactMap {
            if case .result(let output, _) = $0 {
                output
            } else {
                nil
            }
        }.first
        #expect(text == "Tools are disabled.", "Result text must come from the model's follow-up response.")
    }

    @Test("Discards tool calls and surfaces maxTokens when stop reason is max_tokens")
    func discardsToolCallsOnMaxTokensFinish() async throws {
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("max_tokens")],
        ])
        let session = makeSession(clientFactory: { _ in mock })
        let events = try await collect(session)

        #expect(mock.callCount == 1, "No follow-up request should be issued after max_tokens finish.")
        #expect(!events.contains(where: { if case .toolCallRequested = $0 { true } else { false } }),
                "toolCallRequested must not appear when tool calls are discarded due to max_tokens finish.")
        let finishReason = events.compactMap {
            if case .result(_, let reason) = $0 { reason } else { nil }
        }.first
        #expect(finishReason == .maxTokens)
    }

    @Test("Max-token tool-only turn does not reuse prior assistant text")
    func maxTokenToolOnlyTurnDoesNotReusePriorAssistantText() async throws {
        let mock = MockHTTPClient(responses: [
            [.textDelta("Old answer"), .stopReason("end_turn")],
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("max_tokens")],
        ])
        let session = makeSession(clientFactory: { _ in mock })

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

    @Test("Preserves empty assistant turn in request history")
    func preservesEmptyAssistantTurnInRequestHistory() async throws {
        let mock = MockHTTPClient(responses: [
            [.stopReason("end_turn")],
            [.textDelta("second"), .stopReason("end_turn")],
        ])
        let session = makeSession(clientFactory: { _ in mock })

        _ = try await collect(session, "one")
        _ = try await collect(session, "two")

        let secondRequest = mock.capturedRequests[1]
        let roles = secondRequest.messages.map(\.role)
        #expect(roles == [.user, .assistant, .user])
        guard case .text(let text) = secondRequest.messages[1].content.first else {
            Issue.record("Expected empty assistant text block")
            return
        }
        #expect(text == "")
    }

    @Test("Structured generation discards tool calls on max_tokens finish and does not follow up")
    func structuredGeneration_discardsToolCallsOnMaxTokensFinish() async throws {
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("max_tokens")],
        ])
        let session = makeSession(clientFactory: { _ in mock })

        let stream: StructuredInferenceStream<StructuredDecision> = try await session.generateStream(
            prompt: "probe",
            parameters: InferenceRequestParameters(),
        )
        var sawToolCallRequested = false
        // The stream throws because max_tokens produces no decodable result — that is
        // correct behaviour. We only care that no tool was invoked and no follow-up was sent.
        do {
            for try await event in stream {
                if case .toolCallRequested = event { sawToolCallRequested = true }
            }
        } catch {}

        #expect(mock.callCount == 1, "No follow-up request should be issued after max_tokens finish.")
        #expect(!sawToolCallRequested, "toolCallRequested must not appear when tool calls are discarded.")
    }

    @Test("Regular inference emits toolHookFired events from tool execution")
    func inference_emitsHookFiredEvents() async throws {
        let spy = HookSpy()
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-h1", name: "echo", argsJSON: #"{"message":"probe"}"#), .stopReason("tool_use")],
            [.textDelta("done"), .stopReason("end_turn")],
        ])
        let session = AnthropicInferenceSession(
            credentials: MockAPIKeyProvider("test-key"),
            defaultModel: "test-model",
            systemPrompt: nil,
            toolRuntime: testToolRuntime(
                registry: ToolRegistry([AnyAgentTool(InferenceEchoTool())]),
                hooks: [AnyToolHook(spy)],
            ),
            clientFactory: { _ in mock },
        )

        let events = try await collect(session)
        #expect(events.contains(where: { if case .toolHookFired = $0 { true } else { false } }),
                "toolHookFired must appear in the regular inference stream")
        #expect(spy.fired, "Hook must have fired during regular tool execution")
    }

    @Test("Structured generation emits toolHookFired events from tool execution")
    func structuredGeneration_emitsHookFiredEvents() async throws {
        let spy = HookSpy()
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-h1", name: "echo", argsJSON: #"{"message":"probe"}"#), .stopReason("tool_use")],
            [.textDelta(#"{"answer":"done"}"#), .stopReason("end_turn")],
        ])
        let session = AnthropicInferenceSession(
            credentials: MockAPIKeyProvider("test-key"),
            defaultModel: "test-model",
            systemPrompt: nil,
            toolRuntime: testToolRuntime(
                registry: ToolRegistry([AnyAgentTool(InferenceEchoTool())]),
                hooks: [AnyToolHook(spy)],
            ),
            clientFactory: { _ in mock },
        )

        let stream: StructuredInferenceStream<StructuredDecision> = try await session.generateStream(
            prompt: "probe",
            parameters: InferenceRequestParameters(),
        )
        var sawHookEvent = false
        for try await event in stream {
            if case .toolHookFired = event { sawHookEvent = true }
        }

        #expect(sawHookEvent, "toolHookFired must appear in the structured generation stream")
        #expect(spy.fired, "Hook must have fired during structured tool execution")
    }
}
#endif
