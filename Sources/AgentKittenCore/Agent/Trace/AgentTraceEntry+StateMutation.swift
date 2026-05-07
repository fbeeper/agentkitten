// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension AgentTraceEntry.Kind {
    /// Durable record of a session-state mutation.
    ///
    /// Value content is intentionally excluded. Only the key and a coarse type
    /// descriptor are recorded so trace and future ledger layers do not
    /// retain scratchpad payloads.
    public struct StateMutation: Sendable, Codable, Equatable, Hashable {
        /// The mutation operation applied to the key.
        public let operation: Operation
        /// The key that changed.
        public let key: String
        /// Optional descriptor of the written value type.
        ///
        /// Present for `.set` mutations and `nil` for removals.
        public let valueType: String?

        /// Creates a trace-safe state mutation record.
        public init(
            operation: Operation,
            key: String,
            valueType: String?
        ) {
            self.operation = operation
            self.key = key
            self.valueType = valueType
        }

        /// The kind of state mutation that occurred.
        public enum Operation: String, Sendable, Codable, Equatable, Hashable {
            /// A key was written or replaced.
            case set
            /// A key was removed.
            case remove
        }
    }
}
