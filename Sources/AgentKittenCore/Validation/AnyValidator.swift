// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

struct AnyValidator<Result: Sendable>: Validator {
    let traceName: String
    private let validateBody: @Sendable (ValidationContext<Result>) async throws -> ValidationResult

    init<V: Validator>(_ validator: V) where V.Result == Result {
        traceName = validator.traceName
        validateBody = validator.validate
    }

    func validate(_ context: ValidationContext<Result>) async throws -> ValidationResult {
        try await validateBody(context)
    }
}
