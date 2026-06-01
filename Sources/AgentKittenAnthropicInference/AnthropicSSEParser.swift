// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenInferenceSupport
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Parses Anthropic's Server-Sent Events stream into typed ``SSEEvent`` values.
enum AnthropicSSEParser {
    #if canImport(Darwin)
    /// Transforms raw `URLSession.AsyncBytes` into a stream of ``SSEEvent`` values.
    ///
    /// The parser accumulates `input_json_delta` fragments per block index until
    /// `content_block_stop`, at which point it emits a `.toolCallReady` event
    /// with the fully assembled arguments JSON.
    static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        makeSSEStream(from: bytes.lines, state: ParserState())
    }
    #else
    /// Drives the parser from a full SSE payload encoded as UTF-8 text.
    static func events(from data: Data) -> AsyncThrowingStream<SSEEvent, Error> {
        let lines = sseLines(from: data)
        return events(fromLines: lines)
    }
    #endif

    /// Drives the parser from a plain string sequence. Package-internal for testing.
    static func events(fromLines lines: [String]) -> AsyncThrowingStream<SSEEvent, Error> {
        makeSSEStream(fromLines: lines, state: ParserState())
    }
}

// MARK: - Parser State

private struct ParserState: SSELineConsumer {
    typealias Event = SSEEvent

    var eventType = ""
    var dataLines: [String] = []
    var toolIDs: [Int: String] = [:]
    var toolNames: [Int: String] = [:]
    var toolArgs: [Int: String] = [:]
    var pendingInputTokens: Int = 0

    mutating func flush() -> [SSEEvent] {
        guard !dataLines.isEmpty else { return [] }
        return dispatch()
    }

    mutating func consume(line: String) -> [SSEEvent] {
        if line.hasPrefix("event:") {
            // Dispatch any buffered data from the previous event before starting a new one.
            // URLSession.AsyncBytes.lines skips blank lines, so blank-line dispatch never fires;
            // dispatching here handles Anthropic's blank-line-free SSE format.
            var events: [SSEEvent] = []
            if !dataLines.isEmpty {
                events = dispatch()
                dataLines = []
            }
            eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return events
        } else if line.hasPrefix("data:") {
            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            dataLines.append(data)
            return []
        } else if line.isEmpty {
            let events = dispatch()
            dataLines = []
            eventType = ""
            return events
        }
        return []
    }

    private mutating func dispatch() -> [SSEEvent] {
        let payload = dataLines.joined(separator: "\n")
        guard
            !payload.isEmpty,
            let jsonData = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return []
        }
        switch eventType {
        case "message_start":
            handleMessageStart(json: json)
            return []
        case "content_block_start":
            handleBlockStart(json: json)
            return []
        case "content_block_delta":
            return handleBlockDelta(json: json)
        case "content_block_stop":
            return handleBlockStop(json: json)
        case "message_delta":
            return handleMessageDelta(json: json)
        case "error":
            return handleError(json: json)
        default:
            return []
        }
    }

    private mutating func handleMessageStart(json: [String: Any]) {
        guard let usage = (json["message"] as? [String: Any])?["usage"] as? [String: Any] else {
            return
        }
        let input = usage["input_tokens"] as? Int ?? 0
        let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        pendingInputTokens = input + cacheCreate + cacheRead
    }

    private mutating func handleBlockStart(json: [String: Any]) {
        guard
            let index = json["index"] as? Int,
            let block = json["content_block"] as? [String: Any],
            let blockType = block["type"] as? String,
            blockType == "tool_use"
        else {
            return
        }
        toolIDs[index] = block["id"] as? String ?? ""
        toolNames[index] = block["name"] as? String ?? ""
        toolArgs[index] = ""
    }

    private mutating func handleBlockDelta(json: [String: Any]) -> [SSEEvent] {
        guard
            let index = json["index"] as? Int,
            let delta = json["delta"] as? [String: Any],
            let deltaType = delta["type"] as? String
        else {
            return []
        }
        switch deltaType {
        case "text_delta":
            if let text = delta["text"] as? String {
                return [.textDelta(text)]
            }
        case "input_json_delta":
            if let partial = delta["partial_json"] as? String {
                toolArgs[index, default: ""] += partial
            }
        default:
            break
        }
        return []
    }

    private mutating func handleBlockStop(json: [String: Any]) -> [SSEEvent] {
        guard let index = json["index"] as? Int else { return [] }
        if let id = toolIDs[index], let name = toolNames[index], let args = toolArgs[index] {
            let argsJSON = args.isEmpty ? "{}" : args
            toolIDs.removeValue(forKey: index)
            toolNames.removeValue(forKey: index)
            toolArgs.removeValue(forKey: index)
            return [.toolCallReady(id: id, name: name, argsJSON: argsJSON)]
        }
        return []
    }

    private func handleMessageDelta(json: [String: Any]) -> [SSEEvent] {
        var events: [SSEEvent] = []
        if let delta = json["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
            events.append(.stopReason(reason))
        }
        let outputTokens = (json["usage"] as? [String: Any])?["output_tokens"] as? Int ?? 0
        events.append(.usage(pendingInputTokens + outputTokens))
        return events
    }

    private func handleError(json: [String: Any]) -> [SSEEvent] {
        let message = (json["error"] as? [String: Any])?["message"] as? String
        return [.error(message ?? "Unknown Anthropic API error.")]
    }
}
#endif
