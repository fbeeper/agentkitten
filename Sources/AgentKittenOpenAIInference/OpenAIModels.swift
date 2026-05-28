// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import Foundation

// MARK: - Request

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let tools: [OpenAITool]?
    let stream: Bool
    let streamOptions: StreamOptions?
    let temperature: Double
    let maxTokens: Int

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
        case maxTokens = "max_tokens"
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
    /// Text content (system, user, assistant without tool calls).
    let content: OpenAIMessageContent?
    /// Tool calls requested by the assistant. Present only on assistant turns.
    let toolCalls: [OpenAIWireToolCall]?
    /// The tool call ID this result responds to. Present only on tool turns.
    let toolCallID: String?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
    }

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }
}

extension OpenAIMessage {
    static func system(_ text: String) -> OpenAIMessage {
        OpenAIMessage(role: .system, content: .text(text), toolCalls: nil, toolCallID: nil)
    }

    static func user(_ text: String) -> OpenAIMessage {
        OpenAIMessage(role: .user, content: .text(text), toolCalls: nil, toolCallID: nil)
    }

    static func assistant(text: String?, toolCalls: [OpenAIWireToolCall]?) -> OpenAIMessage {
        let content: OpenAIMessageContent? = text.flatMap { $0.isEmpty ? nil : .text($0) }
        return OpenAIMessage(role: .assistant, content: content, toolCalls: toolCalls, toolCallID: nil)
    }

    static func toolResult(
        toolCallID: String,
        content: [ToolResultContent],
        isError: Bool,
    ) -> OpenAIMessage {
        let hasImages = content.contains { if case .image = $0 { true } else { false } }
        let msgContent: OpenAIMessageContent
        if hasImages {
            let parts: [OpenAIContentPart] = content.map { item in
                switch item {
                case .text(let text):
                    .text(isError ? "[Error] \(text)" : text)
                case .image(let mediaType, let data):
                    .imageURL(mediaType: mediaType, data: data)
                }
            }
            msgContent = .parts(parts)
        } else {
            let text = content.compactMap { item -> String? in
                guard case .text(let str) = item else { return nil }
                return str
            }.joined(separator: "\n")
            msgContent = .text(isError ? "[Error] \(text)" : text)
        }
        return OpenAIMessage(role: .tool, content: msgContent, toolCalls: nil, toolCallID: toolCallID)
    }
}

// MARK: - Message Content

/// The content of an OpenAI message: either a plain string or a multipart array.
enum OpenAIMessageContent: Encodable {
    case text(String)
    case parts([OpenAIContentPart])

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .text(let str):
            var container = encoder.singleValueContainer()
            try container.encode(str)
        case .parts(let arr):
            var container = encoder.unkeyedContainer()
            for part in arr {
                try container.encode(part)
            }
        }
    }
}

/// A single content part within a multipart message.
enum OpenAIContentPart: Encodable {
    case text(String)
    case imageURL(mediaType: String, data: Data)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let str):
            try container.encode("text", forKey: .type)
            try container.encode(str, forKey: .text)
        case .imageURL(let mediaType, let data):
            try container.encode("image_url", forKey: .type)
            let url = "data:\(mediaType);base64,\(data.base64EncodedString())"
            try container.encode(OpenAIImageURL(url: url), forKey: .imageURL)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    private struct OpenAIImageURL: Encodable {
        let url: String
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
        let parameters: OpenAIJSONValue
    }
}

// MARK: - JSON Value

/// A recursive JSON value used for tool parameter schemas.
///
/// Mirrors ``JSONSchema`` but serializes to the flat JSON format
/// that the OpenAI API expects (e.g., `"type": "string"` rather than
/// a Swift enum case).
indirect enum OpenAIJSONValue: Encodable, Equatable {
    case object([String: OpenAIJSONValue])
    case array([OpenAIJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .object(let dict):
            var container = encoder.container(keyedBy: StringKey.self)
            for (key, value) in dict {
                try container.encode(value, forKey: StringKey(key))
            }
        case .array(let arr):
            var container = encoder.unkeyedContainer()
            for item in arr {
                try container.encode(item)
            }
        case .string(let str):
            var container = encoder.singleValueContainer()
            try container.encode(str)
        case .number(let num):
            var container = encoder.singleValueContainer()
            try container.encode(num)
        case .bool(let flag):
            var container = encoder.singleValueContainer()
            try container.encode(flag)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    private struct StringKey: CodingKey {
        var stringValue: String
        var intValue: Int? {
            nil
        }

        init(_ string: String) {
            stringValue = string
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
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
