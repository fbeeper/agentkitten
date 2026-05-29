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
    ) async throws -> [InferenceEvent<String>] {
        var events: [InferenceEvent<String>] = []
        for try await event in try await session.run(
            UserMessage(text: message),
            parameters: InferenceRequestParameters(),
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
