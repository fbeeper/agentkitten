// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension AgentTraceEntry.Kind {
    /// Validation activity recorded during one turn.
    public struct ValidationInfo: Sendable, Codable, Equatable, Hashable {
        /// The validation result being recorded.
        public enum Result: String, Sendable, Codable, Equatable, Hashable {
            /// Validation succeeded.
            case pass
            /// Validation requested another assistant attempt.
            case feedback
            /// Validation determined the output was invalid.
            case fail
            /// Invalid or incomplete validation was waived under a permissive policy.
            case waived
            /// Validation could not complete due to an error.
            case error
        }

        /// The recorded validation result.
        public let result: Result
        /// Human-readable validation detail for the recorded result.
        public let message: String
        /// Validator identifier recorded with the result.
        public let validator: String

        /// Creates validation trace metadata.
        public init(result: Result, message: String, validator: String) {
            self.result = result
            self.message = message
            self.validator = validator
        }
    }
}
