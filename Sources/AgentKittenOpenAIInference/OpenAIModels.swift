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
    let maxCompletionTokens: Int

    struct StreamOptions: Encodable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case streamOptions = "stream_options"
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
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
