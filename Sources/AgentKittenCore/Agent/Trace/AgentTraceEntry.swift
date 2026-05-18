// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One durable record in the agent trace.
public struct AgentTraceEntry: Sendable, Codable, Equatable, Hashable {
    /// Timestamp captured for a trace entry.
    public struct Timestamp: Sendable, Codable, Equatable, Hashable, Comparable {
        private let instant: ContinuousClock.Instant

        /// Captures a timestamp for the current instant.
        public init() {
            self.init(instant: ContinuousClock().now)
        }

        private init(instant: ContinuousClock.Instant) {
            self.instant = instant
        }

        /// Reconstructs a wall-clock date using a trace anchor.
        ///
        /// - Parameter anchor: AgentTrace timestamp anchor.
        /// - Returns: Wall-clock date derived from the anchor date and monotonic
        ///   duration between the anchor and this timestamp.
        public func date(anchoredAt anchor: AgentTrace.TimestampAnchor) -> Date {
            anchor.date.addingTimeInterval(
                anchor.instant.duration(to: instant) / .seconds(1),
            )
        }

        public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
            lhs.instant < rhs.instant
        }
    }

    /// The semantic payload for this entry.
    public let kind: Kind
    /// Timestamp captured when the entry was recorded.
    public let timestamp: Timestamp
    /// Identifier shared by all entries from one `send()` invocation.
    public let invocationID: InvocationID

    /// Creates a trace entry.
    ///
    /// - Parameters:
    ///   - kind: The semantic payload.
    ///   - timestamp: AgentTrace timestamp.
    ///   - invocationID: Turn grouping identifier.
    public init(
        kind: Kind,
        timestamp: Timestamp = Timestamp(),
        invocationID: InvocationID,
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.invocationID = invocationID
    }
}
