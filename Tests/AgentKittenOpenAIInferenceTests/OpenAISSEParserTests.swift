// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenOpenAIInference
import Testing

@Suite("OpenAI SSE parser (text path)")
struct OpenAISSEParserTests {
    private func collect(_ lines: [String]) async throws -> [OpenAISSEEvent] {
        var events: [OpenAISSEEvent] = []
        for try await event in OpenAISSEParser.events(fromLines: lines) {
            events.append(event)
        }
        return events
    }

    @Test("Parses content deltas")
    func parsesTextDeltas() async throws {
        let events = try await collect([
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"lo"}}]}"#,
            "data: [DONE]",
        ])
        let text = events.compactMap { if case .textDelta(let chunk) = $0 { chunk } else { nil } }.joined()
        #expect(text == "Hello")
    }

    @Test("Parses finish reason")
    func parsesFinishReason() async throws {
        let events = try await collect([
            #"data: {"choices":[{"delta":{"content":"hi"},"finish_reason":"stop"}]}"#,
        ])
        let stop = events.contains { if case .stopReason("stop") = $0 { true } else { false } }
        #expect(stop)
    }

    @Test("Parses usage totals")
    func parsesUsage() async throws {
        let events = try await collect([
            #"data: {"choices":[],"usage":{"total_tokens":42}}"#,
        ])
        let usage = events.compactMap { if case .usage(let total) = $0 { total } else { nil } }
        #expect(usage == [42])
    }

    @Test("Surfaces API errors")
    func parsesError() async throws {
        let events = try await collect([
            #"data: {"error":{"message":"boom"}}"#,
        ])
        let messages = events.compactMap { if case .error(let message) = $0 { message } else { nil } }
        #expect(messages == ["boom"])
    }

    @Test("Ignores blank lines and non-data lines")
    func ignoresNoise() async throws {
        let events = try await collect([
            "",
            ": comment",
            #"data: {"choices":[{"delta":{"content":"x"}}]}"#,
            "",
        ])
        #expect(events.count == 1)
    }
}
#endif
