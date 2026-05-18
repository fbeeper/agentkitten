// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A lightweight runtime error recorded in the agent trace.
extension AgentTraceEntry.Kind {
    public struct ErrorInfo: Sendable, Codable, Equatable, Hashable, Error {
        /// Human-readable error description captured at runtime.
        public let description: String

        /// Creates a trace error from any thrown error.
        ///
        /// - Parameter error: The source error.
        public init(_ error: any Error) {
            description = String(describing: error)
        }

        /// Creates a trace error with an explicit description.
        ///
        /// - Parameter description: Human-readable error text.
        public init(description: String) {
            self.description = description
        }
    }
}
