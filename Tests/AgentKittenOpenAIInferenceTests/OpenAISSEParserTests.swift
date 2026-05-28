// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenOpenAIInference
import Foundation
import Testing

@Suite("OpenAISSEParser")
struct OpenAISSEParserTests {
    @Test("parses text delta events")
    func textDeltaEvents() async throws {
        let lines = [
            chunk(content: "Hello"),
            chunk(content: " world"),
            chunk(stop: "stop"),
            "data: [DONE]",
        ]
        let events = try await collect(OpenAISSEParser.events(fromLines: lines))
        #expect(events.count == 3)
        guard case .textDelta("Hello") = events[0] else { Issue.record("Expected textDelta"); return }
        guard case .textDelta(" world") = events[1] else { Issue.record("Expected textDelta"); return }
        guard case .stopReason("stop") = events[2] else { Issue.record("Expected stopReason"); return }
    }

    @Test("accumulates tool call arguments across chunks")
    func toolCallAccumulation() async throws {
        let lines = [
            toolCallStart(index: 0, id: "call_abc", name: "get_weather"),
            toolCallArgs(index: 0, args: #"{"loc":"#),
            toolCallArgs(index: 0, args: #""Paris"}"#),
            chunk(stop: "tool_calls"),
            "data: [DONE]",
        ]
        let events = try await collect(OpenAISSEParser.events(fromLines: lines))
        let toolCallEvents = events.filter { if case .toolCallReady = $0 { true } else { false } }
        #expect(toolCallEvents.count == 1)
        guard case .toolCallReady(let id, let name, let argsJSON) = toolCallEvents[0] else {
            Issue.record("Expected toolCallReady")
            return
        }
        #expect(id == "call_abc")
        #expect(name == "get_weather")
        #expect(argsJSON == #"{"loc":"Paris"}"#)
    }

    @Test("emits usage from usage-only chunk")
    func usageOnlyChunk() async throws {
        let lines = [
            chunk(content: "Hi"),
            chunk(stop: "stop"),
            usageChunk(prompt: 10, completion: 5, total: 15),
            "data: [DONE]",
        ]
        let events = try await collect(OpenAISSEParser.events(fromLines: lines))
        let usageEvents = events.filter { if case .usage = $0 { true } else { false } }
        #expect(usageEvents.count == 1)
        guard case .usage(let total) = usageEvents[0] else {
            Issue.record("Expected usage event")
            return
        }
        #expect(total == 15)
    }

    @Test("handles multiple tool calls")
    func multipleToolCalls() async throws {
        let lines = [
            toolCallStart(index: 0, id: "call_1", name: "tool_a"),
            toolCallStart(index: 1, id: "call_2", name: "tool_b"),
            toolCallArgs(index: 0, args: #"{"x":1}"#),
            toolCallArgs(index: 1, args: #"{"y":2}"#),
            chunk(stop: "tool_calls"),
            "data: [DONE]",
        ]
        let events = try await collect(OpenAISSEParser.events(fromLines: lines))
        let toolCallEvents = events.filter { if case .toolCallReady = $0 { true } else { false } }
        #expect(toolCallEvents.count == 2)
    }

    @Test("skips blank lines and unknown prefixes")
    func skipsUnknownLines() async throws {
        let lines = [
            "",
            ": keep-alive",
            chunk(content: "Hi"),
            "",
            chunk(stop: "stop"),
            "data: [DONE]",
        ]
        let events = try await collect(OpenAISSEParser.events(fromLines: lines))
        let textEvents = events.filter { if case .textDelta = $0 { true } else { false } }
        #expect(textEvents.count == 1)
    }

    // MARK: - Helpers

    private func collect(
        _ stream: AsyncThrowingStream<OpenAISSEEvent, Error>,
    ) async throws -> [OpenAISSEEvent] {
        var result: [OpenAISSEEvent] = []
        for try await event in stream {
            result.append(event)
        }
        return result
    }

    // MARK: - Chunk Builders

    private func chunk(content: String? = nil, stop: String? = nil) -> String {
        var delta: [String: Any] = [:]
        if let content { delta["content"] = content }
        let choice: [String: Any] = ["delta": delta, "finish_reason": stop as Any]
        return sseData(["choices": [choice]])
    }

    private func toolCallStart(index: Int, id: String, name: String) -> String {
        let call: [String: Any] = ["index": index, "id": id, "function": ["name": name, "arguments": ""]]
        let delta: [String: Any] = ["tool_calls": [call]]
        let choice: [String: Any] = ["delta": delta]
        return sseData(["choices": [choice]])
    }

    private func toolCallArgs(index: Int, args: String) -> String {
        let call: [String: Any] = ["index": index, "function": ["arguments": args]]
        let delta: [String: Any] = ["tool_calls": [call]]
        let choice: [String: Any] = ["delta": delta]
        return sseData(["choices": [choice]])
    }

    private func usageChunk(prompt: Int, completion: Int, total: Int) -> String {
        sseData([
            "choices": [] as [[String: Any]],
            "usage": ["prompt_tokens": prompt, "completion_tokens": completion, "total_tokens": total],
        ])
    }

    private func sseData(_ payload: [String: Any]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let str = String(data: data, encoding: .utf8)
        else {
            return "data: {}"
        }
        return "data: \(str)"
    }
}
#endif
