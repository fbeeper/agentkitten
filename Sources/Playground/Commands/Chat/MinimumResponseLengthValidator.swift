// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten

struct MinimumResponseLengthValidator: Validator<AssistantMessage> {
    let minimumLength: Int

    var traceName: String {
        "MinimumResponseLengthValidator(\(minimumLength))"
    }

    func validate(_ context: ValidationContext<AssistantMessage>) async throws -> ValidationResult {
        guard context.result.text.count >= minimumLength else {
            return .feedback(message: "Response must be at least \(minimumLength) characters.")
        }
        return .pass
    }
}
