// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Type-erased wrapper for a queued turn.
///
/// `AnyQueuedTurn` lets `TurnQueue` hold turns of any result type without
/// knowing the concrete result at the queue level.
struct AnyQueuedTurn: Sendable {
    let id: InvocationID
    private let _isCancelled: @Sendable () async -> Bool
    private let _markRunning: @Sendable (Task<Void, Never>) async -> Bool
    private let _performWork: @Sendable () async -> Void

    init(
        id: InvocationID,
        isCancelled: @Sendable @escaping () async -> Bool,
        markRunning: @Sendable @escaping (Task<Void, Never>) async -> Bool,
        performWork: @Sendable @escaping () async -> Void,
    ) {
        self.id = id
        self._isCancelled = isCancelled
        self._markRunning = markRunning
        self._performWork = performWork
    }

    var isCancelled: Bool { get async { await _isCancelled() } }

    @discardableResult
    func markRunning(task: Task<Void, Never>) async -> Bool {
        await _markRunning(task)
    }

    func performWork() async {
        await _performWork()
    }
}
