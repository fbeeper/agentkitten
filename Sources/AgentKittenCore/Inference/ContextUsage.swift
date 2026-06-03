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

    /// Fill fraction in `0...1`, or `nil` when either value is unknown or context size is zero.
    public var fillPercent: Double? {
        guard case .tokens(let size) = contextSize, size > 0,
              case .tokens(let used) = contextTokens else {
            return nil
        }
        return Double(used) / Double(size)
    }
}
