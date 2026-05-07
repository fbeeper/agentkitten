// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A message in an agent conversation.
///
/// The enum covers the core human–assistant–system exchange plus tool interactions.
/// Values of this type appear in durable trace entries and in live completion payloads.
public enum AgentMessage: Sendable, Codable, Equatable, Hashable {
    /// A message authored by a human user.
    case user(UserMessage)
    /// A response from the AI assistant.
    case assistant(AssistantMessage)
    /// A system-level instruction that frames the assistant's role and behavior.
    case system(SystemMessage)
    /// A tool call requested by the model during a turn.
    case toolCall(ToolCallMessage)
    /// The result of a tool execution, returned to the model.
    case toolResult(ToolResultMessage)
}

/// A message authored by a human user.
///
/// Future additions: attachments, media types.
public struct UserMessage: Sendable, Equatable, Hashable {
    /// The text content of the message.
    public let text: String
    /// The user who authored this message.
    public let sender: UserID

    /// Creates a user message with the given text and sender.
    public init(text: String, sender: UserID = .local) {
        self.text = text
        self.sender = sender
    }
}

extension UserMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case text
        case sender
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        // Backwards-compatible: messages encoded before sender was introduced decode as .local.
        self.sender = try container.decodeIfPresent(UserID.self, forKey: .sender) ?? .local
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(sender, forKey: .sender)
    }
}

/// A message authored by the AI assistant.
///
/// Future additions: directed-to identity, confidence score, source citations.
public struct AssistantMessage: Sendable, Codable, Equatable, Hashable {
    /// The text content of the response.
    public let text: String

    /// Creates an assistant message with the given text.
    public init(text: String) {
        self.text = text
    }
}

/// A system-level instruction that frames the assistant's role and behavior.
///
/// Providers extract system messages from the conversation and pass them to
/// the underlying model as instructions rather than as part of the dialogue.
public struct SystemMessage: Sendable, Codable, Equatable, Hashable {
    /// The instruction text.
    public let text: String

    /// Creates a system message with the given text.
    public init(text: String) {
        self.text = text
    }
}
