// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Reusable logic for splitting conversation history for compaction.
///
/// The boundary is computed by counting turn-start entries in reverse. The
/// `preservedRecentTurnCount` most-recent turns, together with any entries that
/// follow them, form the recent slice. Older entries are candidates for summary
/// or truncation.
public struct TurnPreservationPlan: Sendable {
    private let recentStartIndex: Int

    /// Creates a plan by locating the start of the preserved slice of turns.
    ///
    /// - Parameters:
    ///   - entries: The full history/transcript entries to split.
    ///   - preservedRecentTurnCount: How many recent turns to keep verbatim.
    ///   - isTurnStart: Returns `true` for entries that begin a turn.
    public init<Entry>(
        entries: [Entry],
        preservedRecentTurnCount: Int,
        isTurnStart: (Entry) -> Bool,
    ) {
        recentStartIndex = Self.recentStartIndex(
            in: entries,
            preservedRecentTurnCount: max(0, preservedRecentTurnCount),
            isTurnStart: isTurnStart,
        )
    }

    /// Returns the entries before the preserved recent slice.
    public func olderEntries<Entry>(from entries: [Entry]) -> [Entry] {
        precondition(recentStartIndex <= entries.endIndex, "TurnPreservationPlan used with a shorter entry list.")
        return Array(entries[..<recentStartIndex])
    }

    /// Returns the preserved recent entries.
    public func recentEntries<Entry>(from entries: [Entry]) -> [Entry] {
        precondition(recentStartIndex <= entries.endIndex, "TurnPreservationPlan used with a shorter entry list.")
        return Array(entries[recentStartIndex...])
    }

    private static func recentStartIndex<Entry>(
        in entries: [Entry],
        preservedRecentTurnCount: Int,
        isTurnStart: (Entry) -> Bool,
    ) -> Int {
        guard preservedRecentTurnCount > 0 else {
            return entries.endIndex
        }
        var turnsSeen = 0
        for index in entries.indices.reversed() where isTurnStart(entries[index]) {
            turnsSeen += 1
            if turnsSeen == preservedRecentTurnCount {
                return index
            }
        }
        return entries.startIndex
    }
}
