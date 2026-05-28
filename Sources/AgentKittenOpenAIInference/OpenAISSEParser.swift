// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
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
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let debug = ProcessInfo.processInfo.environment["AGENTKITTEN_DEBUG"] != nil
                    var state = ParserState()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if debug {
                            FileHandle.standardError.write(Data("SSE< [\(line)]\n".utf8))
                        }
                        state.consume(line: line, continuation: continuation)
                    }
                    state.flushToolCalls(continuation: continuation)
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
    #endif

    /// Drives the parser from a full SSE payload encoded as UTF-8 text.
    static func events(from data: Data) -> AsyncThrowingStream<OpenAISSEEvent, Error> {
        let lines = (String(bytes: data, encoding: .utf8) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : String($0) }
        return events(fromLines: lines)
    }

    /// Drives the parser from a plain string sequence. Package-internal for testing.
    static func events(fromLines lines: [String]) -> AsyncThrowingStream<OpenAISSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var state = ParserState()
                for line in lines {
                    state.consume(line: line, continuation: continuation)
                }
                state.flushToolCalls(continuation: continuation)
                continuation.finish()
            }
        }
    }
}

// MARK: - Parser State

private struct ParserState {
    var toolIDs: [Int: String] = [:]
    var toolNames: [Int: String] = [:]
    var toolArgs: [Int: String] = [:]

    /// Emits `.toolCallReady` for all accumulated tool calls, then clears state.
    mutating func flushToolCalls(continuation: AsyncThrowingStream<OpenAISSEEvent, Error>.Continuation) {
        for index in toolIDs.keys.sorted() {
            guard let id = toolIDs[index], let name = toolNames[index] else { continue }
            let args = toolArgs[index] ?? ""
            continuation.yield(.toolCallReady(id: id, name: name, argsJSON: args.isEmpty ? "{}" : args))
        }
        toolIDs = [:]
        toolNames = [:]
        toolArgs = [:]
    }

    mutating func consume(
        line: String,
        continuation: AsyncThrowingStream<OpenAISSEEvent, Error>.Continuation,
    ) {
        guard line.hasPrefix("data:") else { return }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            flushToolCalls(continuation: continuation)
            return
        }
        guard
            !payload.isEmpty,
            let jsonData = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return
        }
        handleChunk(json: json, continuation: continuation)
    }

    private mutating func handleChunk(
        json: [String: Any],
        continuation: AsyncThrowingStream<OpenAISSEEvent, Error>.Continuation,
    ) {
        let choices = json["choices"] as? [[String: Any]] ?? []
        if let choice = choices.first {
            if let delta = choice["delta"] as? [String: Any] {
                handleDelta(delta: delta, continuation: continuation)
            }
            if let finishReason = choice["finish_reason"] as? String, !finishReason.isEmpty {
                if finishReason == "tool_calls" {
                    flushToolCalls(continuation: continuation)
                }
                continuation.yield(.stopReason(finishReason))
            }
        }
        if let usage = json["usage"] as? [String: Any] {
            handleUsage(usage: usage, continuation: continuation)
        }
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown OpenAI API error."
            continuation.yield(.error(message))
        }
    }

    private mutating func handleDelta(
        delta: [String: Any],
        continuation: AsyncThrowingStream<OpenAISSEEvent, Error>.Continuation,
    ) {
        if let content = delta["content"] as? String, !content.isEmpty {
            continuation.yield(.textDelta(content))
        }
        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for callDelta in toolCalls {
                handleToolCallDelta(callDelta)
            }
        }
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

    private func handleUsage(
        usage: [String: Any],
        continuation: AsyncThrowingStream<OpenAISSEEvent, Error>.Continuation,
    ) {
        let total = usage["total_tokens"] as? Int
            ?? (usage["prompt_tokens"] as? Int ?? 0) + (usage["completion_tokens"] as? Int ?? 0)
        continuation.yield(.usage(total))
    }
}
#endif
