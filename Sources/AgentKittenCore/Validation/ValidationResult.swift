// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// The outcome of one validation pass.
public enum ValidationResult: Sendable, Equatable {
    /// Validation succeeded.
    case pass
    /// Validation determined the output is invalid.
    case fail(reason: String)
    /// Validation requests another attempt with feedback for the model.
    case feedback(message: String)
    /// Validation could not complete successfully.
    case error(message: String)
}
