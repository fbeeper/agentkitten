// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Provider-neutral orchestration for context compaction.
///
/// The compactor knows nothing about provider-specific entry shapes. Sessions
/// supply ``RenderedSessionEntry`` values via ``ContextCompactableSession`` and
/// strategies perform the actual truncation or summarization work.
package struct ContextCompactor: Sendable {
    package init() {}

    /// Compacts `session` according to `options`.
    ///
    /// All errors are caught and returned as ``ContextCompactionResult/skipped(_:)``.
    package func compact(
        _ session: some ContextCompactableSession,
        options: ContextCompactionOptions,
        summaryGenerator: ContextCompactionSummaryGenerator,
    ) async -> ContextCompactionResult {
        do {
            return try await options.makeStrategy().compact(
                session,
                summaryGenerator: summaryGenerator,
            )
        } catch let error as InferenceError {
            return .skipped(.inferenceError(error))
        } catch {
            return .skipped(.failed(String(describing: error)))
        }
    }
}

extension ContextCompactionOptions {
    fileprivate func makeStrategy() -> any ContextCompactionStrategy {
        switch self {
        case .summarize(let options):
            SummarizationContextCompactionStrategy(options: options)
        case .truncate(let options):
            TruncationContextCompactionStrategy(options: options)
        case .custom(let strategy):
            CustomContextCompactionStrategy(strategy: strategy)
        }
    }
}

private struct CustomContextCompactionStrategy: ContextCompactionStrategy {
    let strategy: AnyContextCompactionStrategy

    func compact(
        _ session: any ContextCompactableSession,
        summaryGenerator: ContextCompactionSummaryGenerator,
    ) async throws -> ContextCompactionResult {
        try await strategy.compact(
            session,
            summaryGenerator: summaryGenerator,
        )
    }
}

package struct TruncationContextCompactionStrategy: ContextCompactionStrategy, Sendable {
    let options: ContextCompactionOptions.TruncationOptions

    package func compact(
        _ session: any ContextCompactableSession,
        summaryGenerator: ContextCompactionSummaryGenerator,
    ) async throws -> ContextCompactionResult {
        _ = summaryGenerator
        return try await session.applyCompaction(
            summary: nil,
            preservedRecentTurnCount: options.preservedRecentTurnCount,
        )
    }
}

package struct SummarizationContextCompactionStrategy: ContextCompactionStrategy, Sendable {
    let options: ContextCompactionOptions.SummarizationOptions

    package func compact(
        _ session: any ContextCompactableSession,
        summaryGenerator: ContextCompactionSummaryGenerator,
    ) async throws -> ContextCompactionResult {
        let allEntries = await session.compactionEntries()
        let older = olderEntries(
            from: allEntries,
            preservedRecentTurnCount: options.preservedRecentTurnCount,
        )
        let summary: String?
        if older.isEmpty {
            summary = nil
        } else {
            summary = try await summarize(
                entries: older,
                requestSummary: summaryGenerator,
            )
        }
        return try await session.applyCompaction(
            summary: summary,
            preservedRecentTurnCount: options.preservedRecentTurnCount,
        )
    }

    // MARK: - Private

    /// Internal (not private) only to allow direct testing in ContextCompactorTests.
    func summarize(
        entries: [RenderedSessionEntry],
        requestSummary: ContextCompactionSummaryGenerator,
    ) async throws -> String {
        precondition(!entries.isEmpty, "summarize must not be called with an empty entry list")
        let prompt = options.buildPrompt(for: .entries(entries.map(\.rendered)))
        do {
            return try await requestSummary(prompt)
        } catch InferenceError.contextWindowExceeded(let info) {
            guard options.allowsSplitting else {
                throw InferenceError.contextWindowExceeded(info)
            }
            let parts = try split(entries)
            let olderSummary = try await summarize(
                entries: parts.older,
                requestSummary: requestSummary,
            )
            return try await fold(
                summary: olderSummary,
                entries: parts.newer,
                requestSummary: requestSummary,
            )
        }
    }

    private func fold(
        summary: String,
        entries: [RenderedSessionEntry],
        requestSummary: ContextCompactionSummaryGenerator,
    ) async throws -> String {
        guard !entries.isEmpty else {
            return summary
        }

        let prompt = options.buildPrompt(
            for: .summaryAndEntries(summary: summary, entries: entries.map(\.rendered)),
        )
        do {
            return try await requestSummary(prompt)
        } catch InferenceError.contextWindowExceeded(let info) {
            guard options.allowsSplitting else {
                throw InferenceError.contextWindowExceeded(info)
            }
            let parts = try split(entries)
            let foldedOlder = try await fold(
                summary: summary,
                entries: parts.older,
                requestSummary: requestSummary,
            )
            return try await fold(
                summary: foldedOlder,
                entries: parts.newer,
                requestSummary: requestSummary,
            )
        }
    }

    private func split(
        _ entries: [RenderedSessionEntry],
    ) throws -> (older: [RenderedSessionEntry], newer: [RenderedSessionEntry]) {
        let groups = makeGroups(entries)
        guard groups.count > 1 else {
            throw InferenceError.contextWindowExceeded(.init(
                message: "Cannot split compaction input: all entries form a single turn group.",
            ))
        }
        let midpoint = max(1, groups.count / 2)
        return (
            Array(groups[..<midpoint].joined()),
            Array(groups[midpoint...].joined()),
        )
    }

    private func olderEntries(
        from entries: [RenderedSessionEntry],
        preservedRecentTurnCount: Int,
    ) -> [RenderedSessionEntry] {
        let groups = makeGroups(entries)
        let keepCount = min(max(0, preservedRecentTurnCount), groups.count)
        return Array(groups.dropLast(keepCount).joined())
    }

    /// Partitions a flat entry list into turn groups.
    ///
    /// A new group begins at each entry where `isTurnStart` is `true` (a user prompt),
    /// and accumulates all following entries — tool calls, tool results, assistant responses —
    /// until the next turn start or the end of the list. Imbalanced turns (no response,
    /// no tool result) close naturally at the next turn boundary. This grouping is the
    /// primitive that lets splitting and preservation operate on whole turns rather than
    /// individual entries, preventing tool-call/result pairs from being torn apart.
    private func makeGroups(
        _ entries: [RenderedSessionEntry],
    ) -> [[RenderedSessionEntry]] {
        var groups: [[RenderedSessionEntry]] = []
        var pending: [RenderedSessionEntry] = []

        for entry in entries {
            if entry.isTurnStart {
                if !pending.isEmpty {
                    groups.append(pending)
                }
                pending = [entry]
            } else {
                pending.append(entry)
            }
        }
        if !pending.isEmpty {
            groups.append(pending)
        }
        return groups
    }
}
