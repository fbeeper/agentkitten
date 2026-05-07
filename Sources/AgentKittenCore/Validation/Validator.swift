// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Validates a completed assistant response for one turn attempt.
public protocol Validator<Result>: Sendable {
    associatedtype Result: Sendable

    /// Human-readable name used when this validator is recorded in the trace.
    ///
    /// Override this when multiple instances of the same validator type should
    /// appear as distinct entries, for example when they carry different
    /// thresholds or operate in different modes.
    var traceName: String { get }

    /// Validates the provided result context.
    ///
    /// - Parameter context: Validation input for the result.
    /// - Returns: The validation outcome.
    func validate(_ context: ValidationContext<Result>) async throws -> ValidationResult
}

extension Validator {
    public var traceName: String {
        String(describing: Self.self)
    }
}
