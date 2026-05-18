// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A handle for a single queued inference turn.
///
/// ``AgentSession/send(_:)`` returns a `Turn<AssistantMessage>` immediately.
/// Iterate ``events`` to receive ``AgentEvent`` values as they are produced.
/// Call ``cancel()`` to stop generation early.
///
/// Drop semantics are preserved as a convenience — releasing the `Turn`
/// without consuming ``events`` cancels generation — but explicit
/// ``cancel()`` is the preferred contract.
///
/// ```swift
/// // Simple — iterate events directly
/// let session = agent.makeSession()
/// for try await event in try await session.send("hello").events { ... }
///
/// // Explicit cancel
/// let turn: Turn<AssistantMessage> = try await session.send("hello")
/// Task { await turn.cancel() }
/// for try await event in turn.events { ... }
/// ```
public actor Turn<Result: Sendable> {
    // MARK: - Public API

    /// Unique identifier for this turn's invocation.
    public nonisolated var id: InvocationID {
        runtime.id
    }

    /// An async sequence of events produced by this turn.
    ///
    /// Each access returns a fresh ``TurnEventStream`` whose iterator holds a
    /// strong reference to this `Turn`. That keeps inline iteration safe:
    ///
    /// ```swift
    /// for try await event in try await session.send("hello").events { ... }
    /// ```
    public nonisolated var events: TurnEventStream<Result> {
        TurnEventStream(turn: self, stream: runtime.rawEvents)
    }

    // MARK: - Internal API

    nonisolated let runtime: TurnRuntime<Result>

    /// The user-message text; read by `Conversation.processWork()` without actor crossing.
    nonisolated var text: String {
        runtime.text
    }

    /// The user who authored this turn; read by `Conversation.processWork()` without actor crossing.
    nonisolated var sender: UserID {
        runtime.sender
    }

    /// The original per-turn override request.
    nonisolated var requestedTurnOverrides: TurnOverrides {
        runtime.requestedTurnOverrides
    }

    /// The resolved execution environment for this turn.
    nonisolated var executionEnvironment: ExecutionEnvironment {
        runtime.executionEnvironment
    }

    /// Written to by `InferenceDigester.digest()`; `Sendable` so safe to use without actor crossing.
    nonisolated var continuation: AsyncThrowingStream<AgentEvent<Result>, Error>.Continuation {
        runtime.continuation
    }

    /// Cancels this turn's generation.
    ///
    /// Transitions the state to `.cancelled`, cancels the running task (if any),
    /// and finishes the event stream. Safe to call multiple times — subsequent
    /// calls are no-ops.
    public func cancel() {
        if case .cancelled = state {
            return
        }
        let previousState = state
        state = .cancelled
        if case .running(let task) = previousState {
            // The running turn task owns terminal cleanup and will finish the stream
            // after recording cancellation; finishing here would race that path.
            task.cancel()
        } else {
            continuation.finish()
        }
    }

    /// Whether this turn has been cancelled; checked by `Conversation.processWork()`.
    var isCancelled: Bool {
        if case .cancelled = state {
            return true
        }
        if case .running(let task) = state, task.isCancelled {
            return true
        }
        return false
    }

    /// Transitions from `.queued` to `.running`, stores the generation task, and returns
    /// whether the transition succeeded.
    ///
    /// Returns `false` if the turn was already cancelled before the task could be registered,
    /// indicating that the caller must cancel and discard the task.
    @discardableResult
    func markRunning(task: Task<Void, Never>) -> Bool {
        guard case .queued = state else {
            return false
        }
        state = .running(task)
        return true
    }

    // MARK: - Private state

    private enum State {
        case queued
        case running(Task<Void, Never>)
        case cancelled
    }

    private var state: State = .queued

    // MARK: - Init

    init(
        id: InvocationID,
        text: String,
        sender: UserID,
        requestedTurnOverrides: TurnOverrides,
        executionEnvironment: ExecutionEnvironment,
    ) {
        runtime = TurnRuntime(
            id: id,
            text: text,
            sender: sender,
            requestedTurnOverrides: requestedTurnOverrides,
            executionEnvironment: executionEnvironment,
        )
    }

    deinit {
        runtime.continuation.finish()
    }
}
