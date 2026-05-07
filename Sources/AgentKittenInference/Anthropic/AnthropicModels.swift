// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
import Foundation

// MARK: - Request

struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?
    let stream: Bool
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
        case stream
        case temperature
    }
}

struct AnthropicCountTokensRequest: Encodable {
    let model: String
    let system: String?
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools
    }
}

struct AnthropicTokenCountResponse: Decodable {
    let inputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
    }
}

struct AnthropicModelInfoResponse: Decodable {
    let maxInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case maxInputTokens = "max_input_tokens"
    }
}

enum AnthropicModelContextWindow {
    static func standardMaxInputTokens(for model: String) -> Int? {
        guard model.hasPrefix("claude-") else {
            return nil
        }
        // Anthropic's standard Messages API context window is currently 200K.
        // Larger windows require explicit beta opt-in that AgentKitten does not send.
        return 200_000
    }
}

// MARK: - Message

struct AnthropicMessage: Encodable {
    enum Role: String, Encodable {
        case user
        case assistant
    }
    let role: Role
    let content: [AnthropicContent]
}

// MARK: - Content

enum AnthropicContent: Encodable {
    case text(String)
    /// `input` is pre-parsed at construction time; encoding never throws due to malformed JSON.
    case toolUse(id: String, name: String, input: AnthropicJSONValue)
    case toolResult(toolUseID: String, content: [ToolResultContent], isError: Bool)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseId)
            try container.encode(content.map(AnthropicToolResultBlock.init), forKey: .content)
            if isError {
                try container.encode(true, forKey: .isError)
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case name
        case input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

extension AnthropicContent {
    var isErrorToolResult: Bool {
        guard case .toolResult(_, _, let isError) = self else {
            return false
        }
        return isError
    }
}

private enum AnthropicToolResultBlock: Encodable {
    case text(String)
    case image(mediaType: String, data: Data)

    init(_ content: ToolResultContent) {
        switch content {
        case .text(let text):
            self = .text(text)
        case .image(let mediaType, let data):
            self = .image(mediaType: mediaType, data: data)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let data):
            try container.encode("image", forKey: .type)
            try container.encode(
                ImageSource(mediaType: mediaType, data: data.base64EncodedString()),
                forKey: .source
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
    }

    private struct ImageSource: Encodable {
        let type = "base64"
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }
}

// MARK: - Tool

struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: AnthropicJSONValue

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

// MARK: - JSON Value

/// A recursive JSON value used for tool input schemas.
///
/// Mirrors ``JSONSchema`` but serializes to the flat JSON format
/// that the Anthropic API expects (e.g., `"type": "string"` rather than
/// a Swift enum case).
indirect enum AnthropicJSONValue: Encodable, Equatable {
    case object([String: AnthropicJSONValue])
    case array([AnthropicJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    /// Wraps a value produced by `JSONSerialization.jsonObject(with:)`.
    init(_ raw: Any) {
        switch raw {
        case let dict as [String: Any]:
            self = .object(dict.mapValues { AnthropicJSONValue($0) })
        case let arr as [Any]:
            self = .array(arr.map { AnthropicJSONValue($0) })
        case let str as String:
            self = .string(str)
        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                self = .bool(num.boolValue)
            } else {
                self = .number(num.doubleValue)
            }
        default:
            self = .null
        }
    }

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
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

// MARK: - SSE Events

/// Parsed events from the Anthropic SSE stream.
enum SSEEvent {
    case textDelta(String)
    case toolCallReady(id: String, name: String, argsJSON: String)
    case stopReason(String)
    /// Total input tokens consumed by the request (input + cache hits/writes + output).
    case usage(Int)
    case error(String)
}
