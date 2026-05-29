// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Estimated context-window usage for a provider conversation.
public struct ContextUsage: Sendable, Codable, Equatable, Hashable {
    /// Estimated tokens currently held in the provider session context.
    public let contextTokens: TokenCount
    /// The provider/model context window size.
    public let contextSize: TokenCount

    /// Creates a context usage estimate.
    public init(
        contextTokens: TokenCount = .unknown,
        contextSize: TokenCount = .unknown,
    ) {
        self.contextTokens = contextTokens
        self.contextSize = contextSize
    }
}
