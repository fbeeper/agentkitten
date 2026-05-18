// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Estimated context-window usage for a provider conversation.
public struct ContextUsage: Sendable, Codable, Equatable, Hashable {
    /// Estimated tokens currently held in the provider session context.
    public let contextTokens: Int
    /// The provider/model context window, if known.
    public let contextSize: Int?

    /// Creates a context usage estimate.
    public init(
        contextTokens: Int,
        contextSize: Int? = nil,
    ) {
        self.contextTokens = contextTokens
        self.contextSize = contextSize
    }
}
