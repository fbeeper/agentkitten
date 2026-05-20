// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenAnthropicInference
import Testing

// MARK: - Helpers

private func parse(_ lines: String...) async throws -> [SSEEvent] {
    try await AnthropicSSEParser.events(fromLines: Array(lines)).reduce(into: []) { $0.append($1) }
}

private func expectEventSequence(_ actual: [SSEEvent], _ expected: [ExpectedSSEEvent]) {
    #expect(actual.count == expected.count)
    for (actualEvent, expectedEvent) in zip(actual, expected) {
        switch (actualEvent, expectedEvent) {
        case (.textDelta(let actualText), .textDelta(let expectedText)):
            #expect(actualText == expectedText)
        case (
            .toolCallReady(let actualID, let actualName, let actualArgs),
            .toolCallReady(let expectedID, let expectedName, let expectedArgs),
        ):
            #expect(actualID == expectedID)
            #expect(actualName == expectedName)
            #expect(actualArgs == expectedArgs)
        case (.stopReason(let actualReason), .stopReason(let expectedReason)):
            #expect(actualReason == expectedReason)
        case (.usage(let actualTotal), .usage(let expectedTotal)):
            #expect(actualTotal == expectedTotal)
        case (.error(let actualMessage), .error(let expectedMessage)):
            #expect(actualMessage == expectedMessage)
        default:
            Issue.record("Expected \(expectedEvent), got \(actualEvent)")
        }
    }
}

private enum ExpectedSSEEvent: CustomStringConvertible {
    case textDelta(String)
    case toolCallReady(id: String, name: String, argsJSON: String)
    case stopReason(String)
    case usage(Int)
    case error(String)

    var description: String {
        switch self {
        case .textDelta(let text):
            ".textDelta(\(text))"
        case .toolCallReady(let id, let name, let argsJSON):
            ".toolCallReady(id: \(id), name: \(name), argsJSON: \(argsJSON))"
        case .stopReason(let reason):
            ".stopReason(\(reason))"
        case .usage(let total):
            ".usage(\(total))"
        case .error(let message):
            ".error(\(message))"
        }
    }
}

// MARK: - Text generation

@Suite("AnthropicSSEParser text generation")
struct SSEParserTextTests {
    @Test func textDelta_emittedFromContentBlockDelta() async throws {
        let events = try await parse(
            "event: content_block_delta",
            #"data: {"index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
        )
        guard case .textDelta(let text) = events.first else {
            Issue.record("Expected textDelta, got \(events)"); return
        }
        #expect(text == "Hello")
    }

    @Test func multipleTextDeltas_emittedInOrder() async throws {
        let events = try await parse(
            "event: content_block_delta",
            #"data: {"index":0,"delta":{"type":"text_delta","text":"Hi"}}"#,
            "event: content_block_delta",
            #"data: {"index":0,"delta":{"type":"text_delta","text":" there"}}"#,
        )
        let texts = events.compactMap { if case .textDelta(let text) = $0 { text } else { nil } }
        #expect(texts == ["Hi", " there"])
    }

    @Test func stopReason_emittedFromMessageDelta() async throws {
        let events = try await parse(
            "event: message_delta",
            #"data: {"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}"#,
        )
        expectEventSequence(events, [
            .stopReason("end_turn"),
            .usage(5),
        ])
    }

    @Test func usage_combinesInputAndOutputTokens() async throws {
        // input(10) + cacheCreate(2) + cacheRead(3) + output(5) = 20
        let usageData = #"{"input_tokens":10,"cache_creation_input_tokens":2,"cache_read_input_tokens":3}"#
        let messageStart = #"data: {"message":{"usage":\#(usageData)}}"#
        let events = try await parse(
            "event: message_start",
            messageStart,
            "event: message_delta",
            #"data: {"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}"#,
        )
        expectEventSequence(events, [
            .stopReason("end_turn"),
            .usage(20),
        ])
    }

    @Test func multilineDataPayload_joinedBeforeDispatch() async throws {
        let events = try await parse(
            "event: content_block_delta",
            #"data: {"index":0,"delta":{"type":"text_delta","#,
            #"data: "text":"Hello"}}"#,
        )
        expectEventSequence(events, [
            .textDelta("Hello"),
        ])
    }
}

// MARK: - Tool calls

@Suite("AnthropicSSEParser tool calls")
struct SSEParserToolTests {
    @Test func toolCall_assembledFromDeltasAtBlockStop() async throws {
        let events = try await parse(
            "event: content_block_start",
            #"data: {"index":1,"content_block":{"type":"tool_use","id":"tool-1","name":"search"}}"#,
            "event: content_block_delta",
            #"data: {"index":1,"delta":{"type":"input_json_delta","partial_json":"{\"q\":"}}"#,
            "event: content_block_delta",
            #"data: {"index":1,"delta":{"type":"input_json_delta","partial_json":"\"test\"}"}}"#,
            "event: content_block_stop",
            #"data: {"index":1}"#,
        )
        guard case .toolCallReady(let id, let name, let argsJSON) = events.first else {
            Issue.record("Expected toolCallReady, got \(events)")
            return
        }
        #expect(id == "tool-1")
        #expect(name == "search")
        #expect(argsJSON == #"{"q":"test"}"#)
    }

    @Test func toolCall_emptyArgsFallsBackToBraces() async throws {
        let events = try await parse(
            "event: content_block_start",
            #"data: {"index":0,"content_block":{"type":"tool_use","id":"t","name":"noop"}}"#,
            "event: content_block_stop",
            #"data: {"index":0}"#,
        )
        guard case .toolCallReady(_, _, let argsJSON) = events.first else {
            Issue.record("Expected toolCallReady, got \(events)")
            return
        }
        #expect(argsJSON == "{}")
    }

    @Test func multipleToolCalls_trackedByIndex() async throws {
        let events = try await parse(
            "event: content_block_start",
            #"data: {"index":0,"content_block":{"type":"tool_use","id":"id-0","name":"alpha"}}"#,
            "event: content_block_start",
            #"data: {"index":1,"content_block":{"type":"tool_use","id":"id-1","name":"beta"}}"#,
            "event: content_block_delta",
            #"data: {"index":0,"delta":{"type":"input_json_delta","partial_json":"{\"x\":1}"}}"#,
            "event: content_block_delta",
            #"data: {"index":1,"delta":{"type":"input_json_delta","partial_json":"{\"y\":2}"}}"#,
            "event: content_block_stop",
            #"data: {"index":0}"#,
            "event: content_block_stop",
            #"data: {"index":1}"#,
        )
        expectEventSequence(events, [
            .toolCallReady(id: "id-0", name: "alpha", argsJSON: #"{"x":1}"#),
            .toolCallReady(id: "id-1", name: "beta", argsJSON: #"{"y":2}"#),
        ])
    }

    @Test func nonToolContentBlock_ignoredAtStart() async throws {
        let events = try await parse(
            "event: content_block_start",
            #"data: {"index":0,"content_block":{"type":"text"}}"#,
            "event: content_block_stop",
            #"data: {"index":0}"#,
        )
        #expect(events.isEmpty)
    }
}

// MARK: - Error handling

@Suite("AnthropicSSEParser error handling")
struct SSEParserErrorTests {
    @Test func errorEvent_emittedWithMessage() async throws {
        let events = try await parse(
            "event: error",
            #"data: {"error":{"type":"overloaded_error","message":"API overloaded"}}"#,
        )
        expectEventSequence(events, [
            .error("API overloaded"),
        ])
    }

    @Test func unknownEventType_silentlyIgnored() async throws {
        let events = try await parse(
            "event: ping",
            #"data: {"type":"ping"}"#,
        )
        #expect(events.isEmpty)
    }

    @Test func malformedJSON_silentlyIgnored() async throws {
        let events = try await parse(
            "event: content_block_delta",
            "data: not-json",
        )
        #expect(events.isEmpty)
    }

    @Test func eofFlush_dispatchesPendingEvent() async throws {
        // No trailing blank line — flush fires at EOF.
        let events = try await parse(
            "event: message_delta",
            #"data: {"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}"#,
        )
        expectEventSequence(events, [
            .stopReason("end_turn"),
            .usage(1),
        ])
    }
}
