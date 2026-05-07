// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// An async sequence of ``AgentEvent`` values produced by a ``Turn``.
///
/// `TurnEventStream` retains the source `Turn` for the lifetime of iteration so
/// inline use remains safe:
///
/// ```swift
/// for try await event in try await session.send("hello").events { ... }
/// ```
public struct TurnEventStream<Result: Sendable>: AsyncSequence {
    public typealias Element = AgentEvent<Result>

    private let turn: Turn<Result>
    private let stream: AsyncThrowingStream<AgentEvent<Result>, Error>

    init(turn: Turn<Result>, stream: AsyncThrowingStream<AgentEvent<Result>, Error>) {
        self.turn = turn
        self.stream = stream
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(turn: turn, base: stream.makeAsyncIterator())
    }

    /// Iterator for one consumer task.
    ///
    /// `AsyncIteratorProtocol` does not require `Sendable`, and this iterator
    /// is intentionally treated as single-consumer state. The retained `Turn`
    /// only guarantees lifetime while the iterator stays alive inside that one
    /// consumer task; moving the iterator across tasks is not a supported use.
    public struct AsyncIterator: AsyncIteratorProtocol {
        private let turn: Turn<Result>
        private var base: AsyncThrowingStream<AgentEvent<Result>, Error>.AsyncIterator

        fileprivate init(
            turn: Turn<Result>,
            base: AsyncThrowingStream<AgentEvent<Result>, Error>.AsyncIterator
        ) {
            self.turn = turn
            self.base = base
        }

        public mutating func next() async throws -> AgentEvent<Result>? {
            try await base.next()
        }
    }
}
