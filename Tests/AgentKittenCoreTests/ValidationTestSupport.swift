// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

struct MinimumLengthValidator: Validator<AssistantMessage> {
    let minimumLength: Int

    var traceName: String {
        "MinimumLengthValidator(\(minimumLength))"
    }

    func validate(_ context: ValidationContext<AssistantMessage>) async throws -> ValidationResult {
        if context.result.text.count >= minimumLength {
            return .pass
        }
        return .feedback(message: "Response must be at least \(minimumLength) characters.")
    }
}

struct TerminalFailureValidator: Validator<AssistantMessage> {
    let reason: String

    func validate(_ context: ValidationContext<AssistantMessage>) async throws -> ValidationResult {
        .fail(reason: reason)
    }
}

struct ThrowingValidator: Validator<AssistantMessage> {
    let message: String

    func validate(_ context: ValidationContext<AssistantMessage>) async throws -> ValidationResult {
        throw ValidationTestError(message: message)
    }
}

struct ValidationTestError: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

struct OrderedValidator: Validator<AssistantMessage> {
    let result: ValidationResult
    let recorder: ValidationRecorder
    let label: String

    var traceName: String {
        label
    }

    func validate(_ context: ValidationContext<AssistantMessage>) async throws -> ValidationResult {
        await recorder.record(label)
        return result
    }
}

actor ValidationRecorder {
    private var labels: [String] = []

    func record(_ label: String) {
        labels.append(label)
    }

    func recordedLabels() -> [String] {
        labels
    }
}

actor FlakyValidationRecorder {
    private var count = 0

    func nextResult(errorMessage: String) -> ValidationResult {
        count += 1
        return if count == 1 {
            .error(message: errorMessage)
        } else {
            .pass
        }
    }

    func attempts() -> Int {
        count
    }
}

struct FlakyValidator: Validator<AssistantMessage> {
    let recorder: FlakyValidationRecorder
    let errorMessage: String

    func validate(_ context: ValidationContext<AssistantMessage>) async throws -> ValidationResult {
        await recorder.nextResult(errorMessage: errorMessage)
    }
}
