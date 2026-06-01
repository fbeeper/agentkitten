// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A stateful, line-by-line SSE consumer.
package protocol SSELineConsumer<Event> {
    associatedtype Event: Sendable
    /// Called for each line in the stream. Returns any events to yield.
    mutating func consume(line: String) -> [Event]
    /// Called once after all lines have been consumed (EOF). Returns any remaining events.
    mutating func flush() -> [Event]
}

extension SSELineConsumer {
    package mutating func flush() -> [Event] {
        []
    }
}

/// Drives an ``SSELineConsumer`` over an async line sequence with full Task lifecycle management.
///
/// Handles cancellation, debug logging, and error propagation uniformly across SSE providers.
package func makeSSEStream<S: AsyncSequence & Sendable, State: SSELineConsumer & Sendable>(
    from lines: S,
    state: State,
) -> AsyncThrowingStream<State.Event, Error> where S.Element == String {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let debug = ProcessInfo.processInfo.environment["AGENTKITTEN_DEBUG"] != nil
                var localState = state
                for try await line in lines {
                    try Task.checkCancellation()
                    if debug {
                        FileHandle.standardError.write(Data("SSE< [\(line)]\n".utf8))
                    }
                    for event in localState.consume(line: line) {
                        continuation.yield(event)
                    }
                }
                for event in localState.flush() {
                    continuation.yield(event)
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Converts a UTF-8 encoded SSE payload to a normalised line array.
///
/// Splits on `\n`, preserves blank lines for SSE event boundaries, and strips a trailing
/// `\r` from each line so CRLF-delimited payloads are handled correctly.
package func sseLines(from data: Data) -> [String] {
    guard let lines = String(bytes: data, encoding: .utf8) else {
        return []
    }
    return lines
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : String($0)
        }
}

/// Convenience overload that drives an ``SSELineConsumer`` over a pre-materialized line array.
package func makeSSEStream<State: SSELineConsumer & Sendable>(
    fromLines lines: [String],
    state: State,
) -> AsyncThrowingStream<State.Event, Error> {
    makeSSEStream(
        from: AsyncStream { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        },
        state: state,
    )
}
#endif
