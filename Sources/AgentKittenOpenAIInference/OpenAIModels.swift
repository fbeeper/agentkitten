// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import Foundation

// MARK: - Request

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
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

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(streamOptions, forKey: .streamOptions)
        // o-series reasoning models require max_completion_tokens and reject temperature.
        if Self.isReasoningModel(model) {
            try container.encode(maxTokens, forKey: .maxCompletionTokens)
        } else {
            try container.encode(temperature, forKey: .temperature)
            try container.encode(maxTokens, forKey: .maxTokens)
        }
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case streamOptions = "stream_options"
        case temperature
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
    }

    /// Returns true for OpenAI o-series reasoning models (o1, o3, o4-mini, …).
    ///
    /// These models require `max_completion_tokens` instead of `max_tokens` and do not
    /// accept a `temperature` parameter.
    static func isReasoningModel(_ model: String) -> Bool {
        guard model.count >= 2, model.hasPrefix("o") else { return false }
        return model[model.index(after: model.startIndex)].isNumber
    }
}

// MARK: - Message

/// A single message in an OpenAI Chat Completions history.
struct OpenAIMessage: Encodable {
    enum Role: String, Encodable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
    }

    enum CodingKeys: String, CodingKey {
        case role, content
    }
}

extension OpenAIMessage {
    static func system(_ text: String) -> OpenAIMessage {
        OpenAIMessage(role: .system, content: text)
    }

    static func user(_ text: String) -> OpenAIMessage {
        OpenAIMessage(role: .user, content: text)
    }

    static func assistant(_ text: String) -> OpenAIMessage {
        OpenAIMessage(role: .assistant, content: text)
    }
}

// MARK: - SSE Events

/// Parsed events from the OpenAI Chat Completions SSE stream.
enum OpenAISSEEvent {
    case textDelta(String)
    case stopReason(String)
    /// Total tokens consumed by the request (prompt + completion).
    case usage(Int)
    case error(String)
}
#endif
