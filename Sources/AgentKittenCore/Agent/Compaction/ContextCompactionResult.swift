// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Result of a context compaction attempt.
public enum ContextCompactionResult: Sendable, Codable, Equatable, Hashable {
    /// Provider context was compacted.
    case compacted(Compacted)
    /// Provider context was not compacted.
    case skipped(SkipReason)

    /// Whether this result represents a successful compaction.
    public var didCompact: Bool {
        switch self {
        case .compacted:
            true
        case .skipped:
            false
        }
    }

    /// Metadata for a successful context compaction.
    public struct Compacted: Sendable, Codable, Equatable, Hashable {
        /// Context usage before compaction.
        public let usageBefore: ContextUsage
        /// Context usage after compaction.
        public let usageAfter: ContextUsage

        /// Creates metadata for a successful context compaction.
        public init(
            usageBefore: ContextUsage,
            usageAfter: ContextUsage,
        ) {
            self.usageBefore = usageBefore
            self.usageAfter = usageAfter
        }
    }

    /// Reason context compaction was skipped.
    public enum SkipReason: Sendable, Codable, Equatable, Hashable {
        /// Automatic compaction was disabled for the turn.
        case disabled
        /// The session was released before queued compaction ran.
        case sessionReleased
        /// No provider conversation has been created for this session.
        case noActiveConversation
        /// A new provider conversation was created, so there was no retained context to compact.
        case conversationReplaced
        /// The estimated context usage did not meet the automatic compaction trigger.
        case triggerNotMet(ContextUsage)
        /// The provider failed while attempting compaction with a typed inference error.
        case inferenceError(InferenceError)
        /// The provider failed while attempting compaction due to an unexpected error.
        case failed(String)
    }
}
