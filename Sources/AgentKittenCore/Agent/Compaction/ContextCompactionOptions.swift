// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Options for manual or automatic context compaction.
public enum ContextCompactionOptions: Sendable, Equatable, Hashable {
    /// Compact by summarizing older context and preserving recent turns.
    case summarize(SummarizationOptions)
    /// Compact by dropping older context and preserving recent turns.
    case truncate(TruncationOptions)
    /// Compact with a caller-supplied strategy.
    case custom(AnyContextCompactionStrategy)

    /// Options for summarization-based context compaction.
    public struct SummarizationOptions: Sendable, Equatable, Hashable {
        /// Controls the system prompt used when requesting a summary from the model.
        public enum Prompt: Sendable, Equatable, Hashable {
            /// Uses the built-in summarization preamble.
            case standard
            /// Uses the built-in preamble with additional instructions appended.
            case appending(String)
            /// Replaces the built-in preamble entirely; the client owns the full prompt.
            case custom(String)
        }

        /// Number of recent user/assistant turns the provider should preserve after the summary.
        public let preservedRecentTurnCount: Int
        /// The system prompt used when requesting a summary from the model.
        public let prompt: Prompt
        /// Whether to attempt splitting the history into smaller chunks when the full history
        /// exceeds the model context. When `false`, the context-window error is rethrown directly.
        public let allowsSplitting: Bool

        /// Creates summarization compaction options.
        public init(
            preservedRecentTurnCount: Int = 2,
            prompt: Prompt = .standard,
            allowsSplitting: Bool = true
        ) {
            self.preservedRecentTurnCount = preservedRecentTurnCount
            self.prompt = prompt
            self.allowsSplitting = allowsSplitting
        }
    }

    /// Options for truncation-based context compaction.
    public struct TruncationOptions: Sendable, Equatable, Hashable {
        /// Number of recent user/assistant turns the provider should preserve.
        public let preservedRecentTurnCount: Int

        /// Creates truncation compaction options.
        public init(preservedRecentTurnCount: Int = 2) {
            self.preservedRecentTurnCount = preservedRecentTurnCount
        }
    }

    /// Creates default compaction options.
    public init() {
        self = .summarize(.init())
    }
}

/// A type-erased custom context compaction strategy.
///
/// Equality and hashing are based on ``id`` only so callers can store strategies inside
/// ``ContextCompactionOptions`` while supplying arbitrary async compaction behavior.
public struct AnyContextCompactionStrategy: Sendable, Equatable, Hashable {
    /// Stable caller-defined identity for equality and hashing.
    public let id: String
    private let body:
        @Sendable (any ContextCompactableSession, ContextCompactionSummaryGenerator)
        async throws -> ContextCompactionResult

    /// Creates a custom compaction strategy.
    ///
    /// - Parameters:
    ///   - id: Stable identity for equality and hashing.
    ///   - body: Async compaction implementation.
    public init(
        id: String,
        body: @escaping @Sendable (
            any ContextCompactableSession,
            ContextCompactionSummaryGenerator
        ) async throws -> ContextCompactionResult
    ) {
        self.id = id
        self.body = body
    }

    /// Runs the custom compaction behavior.
    public func compact(
        _ session: any ContextCompactableSession,
        summaryGenerator: ContextCompactionSummaryGenerator
    ) async throws -> ContextCompactionResult {
        try await body(session, summaryGenerator)
    }

    public static func == (
        lhs: AnyContextCompactionStrategy,
        rhs: AnyContextCompactionStrategy
    ) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ContextCompactionOptions.SummarizationOptions {
    func buildPrompt(for request: CompactionRequest) -> String {
        var parts: [String]
        switch prompt {
        case .standard:
            parts = [
                AgentKittenLocalization.string("contextCompaction.summarizeHistory"),
                AgentKittenLocalization.string("contextCompaction.preserveFacts"),
            ]
        case .appending(let instructions):
            parts = [
                AgentKittenLocalization.string("contextCompaction.summarizeHistory"),
                AgentKittenLocalization.string("contextCompaction.preserveFacts"),
                AgentKittenLocalization.formattedString(
                    "contextCompaction.additionalInstructionsFormat", instructions),
            ]
        case .custom(let override):
            parts = [override]
        }

        switch request {
        case .entries(let rendered):
            parts.append(AgentKittenLocalization.string("contextCompaction.historyLabel"))
            parts.append(rendered.joined(separator: "\n\n"))
        case .summaryAndEntries(let summary, let rendered):
            parts.append(AgentKittenLocalization.string("contextCompaction.existingSummaryLabel"))
            parts.append(summary)
            parts.append(AgentKittenLocalization.string("contextCompaction.newerHistoryLabel"))
            parts.append(rendered.joined(separator: "\n\n"))
        }

        return parts.joined(separator: "\n\n")
    }
}
