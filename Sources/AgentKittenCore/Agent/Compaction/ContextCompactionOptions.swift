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
        /// Number of recent user/assistant turns the provider should preserve after the summary.
        public let preservedRecentTurnCount: Int
        /// Whether to attempt splitting the history into smaller chunks when the full history
        /// exceeds the model context. When `false`, the context-window error is rethrown directly.
        public let allowsSplitting: Bool
        /// Format string for the built-in summarization prompt; takes one `%@` argument for
        /// the rendered history block.
        ///
        /// A best-effort check verifies the expected placeholder count at init time, but cannot
        /// guarantee the format string produces correct output. Callers are responsible for
        /// verifying behaviour end-to-end.
        public let summaryInstructionFormat: String
        /// Label prepended to the history block.
        public let historyLabel: String
        /// Label prepended to the existing older-history summary block.
        public let existingSummaryLabel: String
        /// Label prepended to the newer history block when folding into an existing summary.
        public let newerHistoryLabel: String

        /// Creates summarization compaction options.
        public init(
            preservedRecentTurnCount: Int = 2,
            allowsSplitting: Bool = true,
            summaryInstructionFormat: String = Self.defaultSummaryInstructionFormat,
            historyLabel: String = Self.defaultHistoryLabel,
            existingSummaryLabel: String = Self.defaultExistingSummaryLabel,
            newerHistoryLabel: String = Self.defaultNewerHistoryLabel,
        ) {
            precondition(
                summaryInstructionFormat.formatPlaceholderCount == 1,
                "summaryInstructionFormat must contain exactly one %@ placeholder for the history block.",
            )
            self.preservedRecentTurnCount = preservedRecentTurnCount
            self.allowsSplitting = allowsSplitting
            self.summaryInstructionFormat = summaryInstructionFormat
            self.historyLabel = historyLabel
            self.existingSummaryLabel = existingSummaryLabel
            self.newerHistoryLabel = newerHistoryLabel
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
        self = .summarize(SummarizationOptions())
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
        ) async throws -> ContextCompactionResult,
    ) {
        self.id = id
        self.body = body
    }

    /// Runs the custom compaction behavior.
    public func compact(
        _ session: any ContextCompactableSession,
        summaryGenerator: ContextCompactionSummaryGenerator,
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
        let history: String = switch request {
        case .entries(let rendered):
            [historyLabel, rendered.joined(separator: "\n\n")].joined(separator: "\n\n")
        case .summaryAndEntries(let summary, let rendered):
            [
                existingSummaryLabel,
                summary,
                newerHistoryLabel,
                rendered.joined(separator: "\n\n"),
            ].joined(separator: "\n\n")
        }
        return String(format: summaryInstructionFormat, history)
    }
}

extension ContextCompactionOptions.SummarizationOptions {
    /// Default format string for the summarization prompt; takes one `%@` for the history block.
    public static let defaultSummaryInstructionFormat =
        """
        Summarize the following prior conversation history for future continuation.

        %@

        Preserve durable facts, user preferences, decisions, unresolved tasks, \
        tool results, and constraints.
        """
    /// Default label prepended to the history block.
    public static let defaultHistoryLabel = "History:"
    /// Default label prepended to the existing older-history summary block.
    public static let defaultExistingSummaryLabel = "Existing older-history summary:"
    /// Default label prepended to the newer history block when folding into an existing summary.
    public static let defaultNewerHistoryLabel = "Newer history to fold into that summary:"
}
