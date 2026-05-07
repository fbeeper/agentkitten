// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Durable, session-lifetime record of all runtime activity.
///
/// Entries accumulate across all turns within one session. Use `invocationID`
/// to group entries by turn. Observe live via ``observe()`` or read a complete
/// queue-consistent snapshot via ``snapshot()``.
///
/// Tool-call and tool-result messages are recorded eagerly. If a turn is later
/// cancelled or fails, trace entries may still contain those partial tool
/// messages followed by a cancelled or failed terminal outcome.
public actor AgentTrace {
    /// Wall-clock and monotonic-clock origin for trace entry timestamps.
    public struct TimestampAnchor: Sendable, Codable, Equatable, Hashable {
        /// Human-readable wall-clock origin.
        public let date: Date
        let instant: ContinuousClock.Instant

        fileprivate init(
            date: Date = Date(),
            instant: ContinuousClock.Instant = ContinuousClock().now
        ) {
            self.date = date
            self.instant = instant
        }
    }

    private enum Command: Sendable {
        case appendEntry(AgentTraceEntry)
        case registerObserver(
            id: UUID,
            continuation: AsyncStream<AgentTraceEntry>.Continuation
        )
        case removeObserver(id: UUID)
        case snapshot(CheckedContinuation<[AgentTraceEntry], Never>)
    }

    /// All entries applied to retention since this session was created.
    ///
    /// This property is eventually consistent with synchronous recording calls.
    /// Use ``snapshot()`` when the caller needs all earlier queued trace
    /// commands to be applied before reading.
    public private(set) var entries: [AgentTraceEntry] = []
    /// The in-memory retention policy applied to ``entries``.
    public let retentionPolicy: TraceRetentionPolicy
    /// Timestamp anchor captured when this trace was created.
    ///
    /// Use this as an anchor for deriving wall-clock dates from entry
    /// timestamps via ``AgentTraceEntry/Timestamp/date(anchoredAt:)``.
    public nonisolated let timestampAnchor: TimestampAnchor

    private nonisolated let commandContinuation: AsyncStream<Command>.Continuation
    private var observers: [UUID: AsyncStream<AgentTraceEntry>.Continuation] = [:]

    /// Creates an empty trace.
    ///
    /// - Parameter retentionPolicy: In-memory retention policy for `entries`.
    public init(retentionPolicy: TraceRetentionPolicy = .maxTurns(150)) {
        self.retentionPolicy = retentionPolicy
        self.timestampAnchor = TimestampAnchor()
        let commandStream: AsyncStream<Command>
        (commandStream, commandContinuation) = AsyncStream.makeStream(
            bufferingPolicy: .unbounded
        )
        Task { [weak self] in
            for await command in commandStream {
                guard let self else {
                    break
                }
                await self.apply(command)
            }
        }
    }

    deinit {
        commandContinuation.finish()
    }

    /// Creates a live-only stream of entries from queue registration order.
    ///
    /// This method does not replay entries applied before the observer
    /// registration command. Callers that need catch-up should call
    /// ``snapshot()`` before observing.
    ///
    /// - Returns: A fresh live stream for this observer.
    public nonisolated func observe() -> AsyncStream<AgentTraceEntry> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            commandContinuation.yield(.registerObserver(
                id: id,
                continuation: continuation
            ))
            continuation.onTermination = { [commandContinuation] _ in
                commandContinuation.yield(.removeObserver(id: id))
            }
        }
    }

    /// Returns retained entries after all earlier trace commands are applied.
    ///
    /// - Returns: Queue-consistent retained trace entries.
    public nonisolated func snapshot() async -> [AgentTraceEntry] {
        await withCheckedContinuation { continuation in
            commandContinuation.yield(.snapshot(continuation))
        }
    }

    nonisolated func append(_ entry: AgentTraceEntry) {
        commandContinuation.yield(.appendEntry(entry))
    }

    nonisolated func append(
        kind: AgentTraceEntry.Kind,
        invocationID: InvocationID
    ) {
        commandContinuation.yield(.appendEntry(AgentTraceEntry(
            kind: kind,
            timestamp: AgentTraceEntry.Timestamp(),
            invocationID: invocationID
        )))
    }

    private func apply(_ command: Command) {
        switch command {
        case .appendEntry(let entry):
            applyAppend(entry)
        case .registerObserver(let id, let continuation):
            observers[id] = continuation
        case .removeObserver(let id):
            observers[id] = nil
        case .snapshot(let continuation):
            continuation.resume(returning: entries)
        }
    }

    private func applyAppend(_ entry: AgentTraceEntry) {
        entries.append(entry)
        applyRetentionPolicy()
        for continuation in observers.values {
            continuation.yield(entry)
        }
    }

    private func applyRetentionPolicy() {
        switch retentionPolicy {
        case .unbounded:
            return
        case .maxTurns(let limit):
            guard limit > 0 else {
                entries = []
                return
            }

            var seenInvocationIDs: Set<InvocationID> = []
            var turnsToKeep = limit
            var firstEntryIndexToKeep = entries.count

            for index in entries.indices.reversed() {
                let invocationID = entries[index].invocationID
                if seenInvocationIDs.insert(invocationID).inserted {
                    turnsToKeep -= 1
                    if turnsToKeep < 0 {
                        break
                    }
                }
                firstEntryIndexToKeep = index
            }

            guard firstEntryIndexToKeep > 0 else {
                return
            }
            entries.removeFirst(firstEntryIndexToKeep)
        }
    }
}
