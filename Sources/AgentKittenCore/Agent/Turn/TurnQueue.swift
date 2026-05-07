// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Manages the FIFO queue of pending turns and the lifecycle of the single
/// processor task that drains it.
///
/// `TurnQueue` is a value type; actor isolation is provided by the owning actor
/// (currently `AgentSession`). All mutating operations must be called from that actor.
struct TurnQueue {
    private var pendingTurns: [AnyQueuedTurn] = []
    private var processorTask: Task<Void, Never>?

    /// Whether a processor task is currently running.
    var hasProcessorTask: Bool { processorTask != nil }

    /// Appends a type-erased queue item to the end of the queue.
    mutating func enqueue(_ turn: AnyQueuedTurn) {
        pendingTurns.append(turn)
    }

    /// Returns and removes the first queued turn, or `nil` if the queue is empty.
    ///
    /// Synchronous and isolated to the owning actor. Used by the processor loop
    /// to make the emptiness check and `setProcessorTask(nil)` assignment one
    /// uninterrupted critical section.
    mutating func nextPendingTurn() -> AnyQueuedTurn? {
        guard !pendingTurns.isEmpty else {
            return nil
        }
        return pendingTurns.removeFirst()
    }

    /// Sets or clears the current processor task reference.
    mutating func setProcessorTask(_ task: Task<Void, Never>?) {
        processorTask = task
    }
}
