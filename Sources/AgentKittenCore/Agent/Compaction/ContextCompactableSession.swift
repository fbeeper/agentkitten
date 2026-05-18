// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Framework-facing contract for sessions that supply ingredients to ``ContextCompactor``.
///
/// Conforming types expose their conversation history and summarization capability
/// so the framework can compact them. ``ContextCompactor`` calls ``compactionEntries()``
/// to read history, runs the compaction algorithm (splitting, summarization), and calls
/// ``applyCompaction(summary:preservedRecentTurnCount:)`` to write the result back.
/// Sessions never reference ``ContextCompactor`` directly.
///
/// ## History stability guarantee
///
/// The framework always calls ``compactionEntries()``,
/// the summary generator closure, and ``applyCompaction(summary:preservedRecentTurnCount:)``
/// within the ``Conversation`` operation gate. Because ``InferenceSession/run(_:parameters:)``
/// also acquires that gate, the two operations are mutually exclusive: history cannot
/// change between `compactionEntries` and `applyCompaction`. Implementations do not need
/// to snapshot history defensively.
public protocol ContextCompactableSession: Actor {
    /// Returns all conversation history entries as rendered entries for compaction.
    ///
    /// The framework splits these into older (to summarize) and recent (to preserve)
    /// using `preservedRecentTurnCount` from the compaction options.
    func compactionEntries() -> [RenderedSessionEntry]
    /// Replaces the session's history with a compacted form and returns the result.
    ///
    /// When `summary` is non-nil the result is a summary prefix followed by the
    /// most-recent `preservedRecentTurnCount` turns. When `summary` is nil only the
    /// recent turns are kept (truncation).
    ///
    /// History is guaranteed stable when this is called — see the type-level note.
    func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int,
    ) async throws -> ContextCompactionResult
}
