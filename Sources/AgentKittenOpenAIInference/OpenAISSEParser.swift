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
/// Each line contains a complete JSON chunk. Tool call arguments accumulate
/// across multiple chunks (identified by the tool call `index` field) and are
/// emitted as ``OpenAISSEEvent/toolCallReady`` only once fully assembled.
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

    var toolIDs: [Int: String] = [:]
    var toolNames: [Int: String] = [:]
    var toolArgs: [Int: String] = [:]

    mutating func flush() -> [OpenAISSEEvent] {
        flushToolCalls()
    }

    mutating func consume(line: String) -> [OpenAISSEEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return flushToolCalls()
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

    private mutating func flushToolCalls() -> [OpenAISSEEvent] {
        var events: [OpenAISSEEvent] = []
        for index in toolIDs.keys.sorted() {
            guard let id = toolIDs[index], let name = toolNames[index] else { continue }
            let args = toolArgs[index] ?? ""
            events.append(.toolCallReady(id: id, name: name, argsJSON: args.isEmpty ? "{}" : args))
        }
        toolIDs = [:]
        toolNames = [:]
        toolArgs = [:]
        return events
    }

    private mutating func handleChunk(json: [String: Any]) -> [OpenAISSEEvent] {
        var events: [OpenAISSEEvent] = []
        let choices = json["choices"] as? [[String: Any]] ?? []
        if let choice = choices.first {
            if let delta = choice["delta"] as? [String: Any] {
                events += handleDelta(delta: delta)
            }
            if let finishReason = choice["finish_reason"] as? String, !finishReason.isEmpty {
                if finishReason == "tool_calls" {
                    events += flushToolCalls()
                }
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

    private mutating func handleDelta(delta: [String: Any]) -> [OpenAISSEEvent] {
        var events: [OpenAISSEEvent] = []
        if let content = delta["content"] as? String, !content.isEmpty {
            events.append(.textDelta(content))
        }
        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for callDelta in toolCalls {
                handleToolCallDelta(callDelta)
            }
        }
        return events
    }

    private mutating func handleToolCallDelta(_ callDelta: [String: Any]) {
        let index = callDelta["index"] as? Int ?? 0
        if let id = callDelta["id"] as? String {
            toolIDs[index] = id
        }
        if let function = callDelta["function"] as? [String: Any] {
            if let name = function["name"] as? String {
                toolNames[index] = name
            }
            if let args = function["arguments"] as? String {
                toolArgs[index, default: ""] += args
            }
        }
    }

    private func handleUsage(usage: [String: Any]) -> [OpenAISSEEvent] {
        let total = usage["total_tokens"] as? Int
            ?? (usage["prompt_tokens"] as? Int ?? 0) + (usage["completion_tokens"] as? Int ?? 0)
        return [.usage(total)]
    }
}
#endif
