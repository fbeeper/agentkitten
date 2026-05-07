// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A summary-generation closure used by context compaction strategies.
public typealias ContextCompactionSummaryGenerator = @Sendable (String) async throws -> String

/// Package-internal contract for context compaction strategies.
package protocol ContextCompactionStrategy: Sendable {
    /// Compacts `session`, calling `summaryGenerator` to produce summaries when needed.
    /// Strategy implementations may throw; ``ContextCompactor`` catches and normalizes
    /// failures into ``ContextCompactionResult/skipped(_:)``.
    func compact(
        _ session: any ContextCompactableSession,
        summaryGenerator: ContextCompactionSummaryGenerator
    ) async throws -> ContextCompactionResult
}
