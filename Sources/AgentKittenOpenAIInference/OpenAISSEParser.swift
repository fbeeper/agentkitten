// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenInferenceSupport
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Parses OpenAI Chat Completions SSE stream into typed ``OpenAISSEEvent`` values.
///
/// The OpenAI SSE format uses only `data:` fields (no named `event:` fields).
/// Each line contains a complete JSON chunk.
enum OpenAISSEParser {
    #if canImport(Darwin)
    /// Transforms raw `URLSession.AsyncBytes` into a stream of ``OpenAISSEEvent`` values.
    static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<OpenAISSEEvent, Error> {
        makeSSEStream(from: bytes.lines, state: ParserState())
    }
    #else
    /// Drives the parser from a full SSE payload encoded as UTF-8 text.
    static func events(from data: Data) -> AsyncThrowingStream<OpenAISSEEvent, Error> {
        let lines = sseLines(from: data)
        return events(fromLines: lines)
    }
    #endif

    /// Drives the parser from a plain string sequence. Package-internal for testing.
    static func events(fromLines lines: [String]) -> AsyncThrowingStream<OpenAISSEEvent, Error> {
        makeSSEStream(fromLines: lines, state: ParserState())
    }
}

// MARK: - Parser State

private struct ParserState: SSELineConsumer {
    typealias Event = OpenAISSEEvent

    mutating func consume(line: String) -> [OpenAISSEEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return []
        }
        guard
            !payload.isEmpty,
            let jsonData = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return []
        }
        return handleChunk(json: json)
    }

    private func handleChunk(json: [String: Any]) -> [OpenAISSEEvent] {
        var events: [OpenAISSEEvent] = []
        let choices = json["choices"] as? [[String: Any]] ?? []
        if let choice = choices.first {
            if let delta = choice["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                events.append(.textDelta(content))
            }
            if let finishReason = choice["finish_reason"] as? String, !finishReason.isEmpty {
                events.append(.stopReason(finishReason))
            }
        }
        if let usage = json["usage"] as? [String: Any] {
            events += handleUsage(usage: usage)
        }
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown OpenAI API error."
            events.append(.error(message))
        }
        return events
    }

    private func handleUsage(usage: [String: Any]) -> [OpenAISSEEvent] {
        let total = usage["total_tokens"] as? Int
            ?? (usage["prompt_tokens"] as? Int ?? 0) + (usage["completion_tokens"] as? Int ?? 0)
        return [.usage(total)]
    }
}
#endif
