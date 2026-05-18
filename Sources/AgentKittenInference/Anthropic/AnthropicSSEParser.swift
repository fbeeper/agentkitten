// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Parses Anthropic's Server-Sent Events stream into typed ``SSEEvent`` values.
enum AnthropicSSEParser {
    /// Transforms raw `URLSession.AsyncBytes` into a stream of ``SSEEvent`` values.
    ///
    /// The parser accumulates `input_json_delta` fragments per block index until
    /// `content_block_stop`, at which point it emits a `.toolCallReady` event
    /// with the fully assembled arguments JSON.
    static func events(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let debug = ProcessInfo.processInfo.environment["AGENTKITTEN_DEBUG"] != nil
                    var state = ParserState()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if debug { fputs("SSE< [\(line)]\n", stderr) }
                        state.consume(line: line, continuation: continuation)
                    }
                    // Flush any event not terminated by a trailing blank line (EOF-terminated SSE).
                    state.flush(continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Parser State

private struct ParserState {
    var eventType = ""
    var dataLines: [String] = []
    var toolIDs: [Int: String] = [:]
    var toolNames: [Int: String] = [:]
    var toolArgs: [Int: String] = [:]
    var pendingInputTokens: Int = 0

    mutating func flush(continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation) {
        guard !dataLines.isEmpty else { return }
        dispatch(continuation: continuation)
    }

    mutating func consume(
        line: String,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
    ) {
        if line.hasPrefix("event:") {
            // Dispatch any buffered data from the previous event before starting a new one.
            // URLSession.AsyncBytes.lines skips blank lines, so blank-line dispatch never fires;
            // dispatching here handles Anthropic's blank-line-free SSE format.
            if !dataLines.isEmpty {
                dispatch(continuation: continuation)
                dataLines = []
            }
            eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            dataLines.append(data)
        } else if line.isEmpty {
            dispatch(continuation: continuation)
            dataLines = []
            eventType = ""
        }
    }

    private mutating func dispatch(
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
    ) {
        let payload = dataLines.joined()
        guard
            !payload.isEmpty,
            let jsonData = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return
        }
        switch eventType {
        case "message_start":
            handleMessageStart(json: json)
        case "content_block_start":
            handleBlockStart(json: json)
        case "content_block_delta":
            handleBlockDelta(json: json, continuation: continuation)
        case "content_block_stop":
            handleBlockStop(json: json, continuation: continuation)
        case "message_delta":
            handleMessageDelta(json: json, continuation: continuation)
        case "error":
            handleError(json: json, continuation: continuation)
        default:
            break
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

    private mutating func handleBlockDelta(
        json: [String: Any],
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
    ) {
        guard
            let index = json["index"] as? Int,
            let delta = json["delta"] as? [String: Any],
            let deltaType = delta["type"] as? String
        else {
            return
        }
        switch deltaType {
        case "text_delta":
            if let text = delta["text"] as? String {
                continuation.yield(.textDelta(text))
            }
        case "input_json_delta":
            if let partial = delta["partial_json"] as? String {
                toolArgs[index, default: ""] += partial
            }
        default:
            break
        }
    }

    private mutating func handleBlockStop(
        json: [String: Any],
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
    ) {
        guard let index = json["index"] as? Int else { return }
        if let id = toolIDs[index], let name = toolNames[index], let args = toolArgs[index] {
            let argsJSON = args.isEmpty ? "{}" : args
            continuation.yield(.toolCallReady(id: id, name: name, argsJSON: argsJSON))
            toolIDs.removeValue(forKey: index)
            toolNames.removeValue(forKey: index)
            toolArgs.removeValue(forKey: index)
        }
    }

    private func handleMessageDelta(
        json: [String: Any],
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
    ) {
        if let delta = json["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
            continuation.yield(.stopReason(reason))
        }
        let outputTokens = (json["usage"] as? [String: Any])?["output_tokens"] as? Int ?? 0
        continuation.yield(.usage(pendingInputTokens + outputTokens))
    }

    private func handleError(
        json: [String: Any],
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
    ) {
        let message = (json["error"] as? [String: Any])?["message"] as? String
        continuation.yield(.error(message ?? "Unknown Anthropic API error."))
    }
}
