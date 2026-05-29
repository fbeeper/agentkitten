// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation

// MARK: - Request

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let tools: [OpenAITool]?
    let stream: Bool
    let streamOptions: StreamOptions?
    let temperature: Double
    let maxCompletionTokens: Int

    struct StreamOptions: Encodable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream
        case streamOptions = "stream_options"
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
    }
}

// MARK: - Context Window

enum OpenAIModelContextWindow {
    /// Returns the known maximum input-token window for a standard OpenAI model, or `nil` if unknown.
    static func standardMaxInputTokens(for model: String) -> Int? {
        let normalized = model.lowercased()

        switch normalized {
        case "chatgpt-4o-latest":
            return 128_000
        default:
            break
        }

        if normalized.hasPrefix("gpt-5.4") || normalized.hasPrefix("gpt-4.1") {
            return 1_000_000
        }
        if normalized == "gpt-5" || normalized.hasPrefix("gpt-5-") {
            return 400_000
        }
        if normalized.hasPrefix("gpt-4o") {
            return 128_000
        }
        if normalized.hasPrefix("o4-mini") {
            return 200_000
        }

        return nil
    }
}

/// Decoded `/models/{id}` metadata, used to resolve the context window for unknown models.
struct OpenAIModelInfoResponse: Decodable {
    let contextWindow: Int?
    let contextLength: Int?
    let maxContextLength: Int?
    let maxInputTokens: Int?

    var resolvedMaxInputTokens: Int? {
        maxInputTokens ?? contextWindow ?? contextLength ?? maxContextLength
    }

    enum CodingKeys: String, CodingKey {
        case contextWindow = "context_window"
        case contextLength = "context_length"
        case maxContextLength = "max_context_length"
        case maxInputTokens = "max_input_tokens"
    }
}

// MARK: - Message

/// A single message in an OpenAI Chat Completions history.
struct OpenAIMessage: Encodable {
    enum Role: String, Encodable {
        case system
        case user
        case assistant
        case tool
    }

    let role: Role
    /// Text content (system, user, assistant without tool calls, tool results).
    let content: String?
    /// Tool calls requested by the assistant. Present only on assistant turns.
    let toolCalls: [OpenAIWireToolCall]?
    /// The tool call ID this result responds to. Present only on tool turns.
    let toolCallID: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }
}

extension OpenAIMessage {
    static func system(_ text: String) -> OpenAIMessage {
        OpenAIMessage(role: .system, content: text, toolCalls: nil, toolCallID: nil)
    }

    static func user(_ text: String) -> OpenAIMessage {
        OpenAIMessage(role: .user, content: text, toolCalls: nil, toolCallID: nil)
    }

    static func assistant(text: String?, toolCalls: [OpenAIWireToolCall]?) -> OpenAIMessage {
        OpenAIMessage(role: .assistant, content: text, toolCalls: toolCalls, toolCallID: nil)
    }

    static func toolResult(
        toolCallID: String,
        content: [ToolResultContent],
        isError: Bool,
    ) -> OpenAIMessage {
        let text = content.map { item in
            switch item {
            case .text(let str):
                str
            case .image(let mediaType, let data):
                "[Image omitted: \(mediaType), \(data.count) bytes]"
            }
        }.joined(separator: "\n")
        let body = isError ? "[Error] \(text)" : text
        return OpenAIMessage(role: .tool, content: body, toolCalls: nil, toolCallID: toolCallID)
    }
}

// MARK: - Tool Call Wire Format

/// A tool call in an assistant message, as returned by the OpenAI API.
struct OpenAIWireToolCall: Encodable {
    let id: String
    let type: String
    let function: FunctionCall

    struct FunctionCall: Encodable {
        let name: String
        let arguments: String
    }
}

// MARK: - Tool Definition

/// An OpenAI function tool definition for the request.
struct OpenAITool: Encodable {
    let type: String
    let function: FunctionDefinition

    struct FunctionDefinition: Encodable {
        let name: String
        let description: String
        let parameters: InferenceProviderJSONValue
    }
}

// MARK: - Pending Tool Call

/// A pending tool call captured from the OpenAI SSE stream.
struct PendingOpenAIToolCall {
    let id: String
    let name: String
    let argsJSON: String
}

// MARK: - SSE Events

/// Parsed events from the OpenAI Chat Completions SSE stream.
enum OpenAISSEEvent {
    case textDelta(String)
    case toolCallReady(id: String, name: String, argsJSON: String)
    case stopReason(String)
    /// Total tokens consumed by the request (prompt + completion).
    case usage(Int)
    case error(String)
}
#endif
