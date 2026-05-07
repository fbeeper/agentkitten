// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct TurnValidator<Result: Sendable> {
    private struct ValidatorOutcome {
        let validatorName: String
        let result: ValidationResult
    }

    private enum ValidationError: Error {
        case rejected(String)
        case failed(String)
    }

    private enum ValidationStep {
        case completed
        case retryGeneration(UserMessage)
        case retryValidation(Result)
    }

    typealias GenerationStep = @Sendable (UserMessage) async throws -> Result

    let configuration: ValidationConfiguration<Result>
    let sessionState: AgentSession.SessionStateAccess
    let consumer: ConversationEventConsumer

    func run(
        generationStep: GenerationStep,
        userMessage: UserMessage,
        context: AgentSessionRuntime.TurnRuntimeContext<Result>
    ) async throws {
        var retryCount = 0
        var attemptMessage = userMessage
        var resultToRevalidate: Result?

        while true {
            let attempt = try await dispatchAttempt(
                revalidating: resultToRevalidate,
                userMessage: userMessage,
                attemptMessage: attemptMessage,
                generationStep: generationStep,
                context: context
            )
            let nextStep = try await handleValidationOutcome(
                attempt.outcome,
                result: attempt.result,
                retryCount: &retryCount,
                context: context
            )
            switch nextStep {
            case .completed:
                return
            case .retryGeneration(let feedbackMessage):
                resultToRevalidate = nil
                attemptMessage = feedbackMessage
            case .retryValidation(let result):
                resultToRevalidate = result
            }
        }
    }

    private func dispatchAttempt(
        revalidating resultToRevalidate: Result?,
        userMessage: UserMessage,
        attemptMessage: UserMessage,
        generationStep: GenerationStep,
        context: AgentSessionRuntime.TurnRuntimeContext<Result>
    ) async throws -> (result: Result, outcome: ValidatorOutcome) {
        if let resultToRevalidate {
            let validationOutcome = await validate(
                resultToRevalidate,
                against: userMessage,
                invocationID: context.turnRuntime.id,
                sink: context.traceSink
            )
            return (result: resultToRevalidate, outcome: validationOutcome)
        }
        let result = try await generationStep(attemptMessage)
        let validationOutcome = await validate(
            result,
            against: userMessage,
            invocationID: context.turnRuntime.id,
            sink: context.traceSink
        )
        return (result: result, outcome: validationOutcome)
    }

    private func handleValidationOutcome(
        _ outcome: ValidatorOutcome,
        result: Result,
        retryCount: inout Int,
        context: AgentSessionRuntime.TurnRuntimeContext<Result>
    ) async throws -> ValidationStep {
        switch outcome.result {
        case .pass:
            consumer.emitResult(
                result,
                timestamp: Date(),
                on: context.turnRuntime
            )
            return .completed
        case .fail(let reason):
            recordValidation(
                .fail,
                message: reason,
                validator: outcome.validatorName,
                sink: context.traceSink
            )
            throw ValidationError.rejected(reason)
        case .feedback(let message):
            return try await handleValidationFeedback(
                message,
                validatorName: outcome.validatorName,
                result: result,
                retryCount: &retryCount,
                context: context
            )
        case .error(let message):
            return try await handleValidationError(
                message,
                validatorName: outcome.validatorName,
                result: result,
                retryCount: &retryCount,
                context: context
            )
        }
    }

    private func handleValidationFeedback(
        _ message: String,
        validatorName: String,
        result: Result,
        retryCount: inout Int,
        context: AgentSessionRuntime.TurnRuntimeContext<Result>
    ) async throws -> ValidationStep {
        recordValidation(
            .feedback,
            message: message,
            validator: validatorName,
            sink: context.traceSink
        )
        guard retryCount < configuration.maxRetries else {
            try await applyValidationPolicy(
                restrictiveResult: AgentTraceEntry.Kind.ValidationInfo.Result.fail,
                lastAttempt: result,
                reason: message,
                validator: validatorName,
                context: context
            )
            return .completed
        }
        retryCount += 1
        // NOTE: This retry feedback is currently injected into the live
        // conversation, so it can leak into later turns. The intended follow-up
        // is an ephemeral turn-local retry context so validation guidance affects
        // only the current response attempt.
        return .retryGeneration(configuration.makeRetryFeedbackMessage(from: message))
    }

    private func handleValidationError(
        _ message: String,
        validatorName: String,
        result: Result,
        retryCount: inout Int,
        context: AgentSessionRuntime.TurnRuntimeContext<Result>
    ) async throws -> ValidationStep {
        guard retryCount < configuration.maxRetries else {
            try await applyValidationPolicy(
                restrictiveResult: AgentTraceEntry.Kind.ValidationInfo.Result.error,
                lastAttempt: result,
                reason: message,
                validator: validatorName,
                context: context
            )
            return .completed
        }
        retryCount += 1
        return .retryValidation(result)
    }

    private func validate(
        _ result: Result,
        against userMessage: UserMessage,
        invocationID: InvocationID,
        sink: TurnTraceSink
    ) async -> ValidatorOutcome {
        let context = ValidationContext(
            result: result,
            userMessage: userMessage,
            invocationID: invocationID,
            sessionState: sessionState
        )
        for validator in configuration.validators {
            do {
                let result = try await validator.validate(context)
                if result == .pass {
                    recordValidation(
                        .pass,
                        message: AgentKittenLocalization.string("validation.validationPassed"),
                        validator: validator.traceName,
                        sink: sink
                    )
                    continue
                }
                return ValidatorOutcome(validatorName: validator.traceName, result: result)
            } catch {
                return ValidatorOutcome(
                    validatorName: validator.traceName,
                    result: .error(message: String(describing: error))
                )
            }
        }
        return ValidatorOutcome(validatorName: "Validation", result: .pass)
    }

    private func applyValidationPolicy(
        restrictiveResult: AgentTraceEntry.Kind.ValidationInfo.Result,
        lastAttempt: Result,
        reason: String,
        validator: String,
        context: AgentSessionRuntime.TurnRuntimeContext<Result>
    ) async throws {
        switch configuration.policy {
        case .restrictive:
            recordValidation(
                restrictiveResult,
                message: reason,
                validator: validator,
                sink: context.traceSink
            )
            throw ValidationError.failed(reason)
        case .permissive:
            recordValidation(
                .waived,
                message: reason,
                validator: validator,
                sink: context.traceSink
            )
            consumer.emitResult(
                lastAttempt,
                timestamp: Date(),
                on: context.turnRuntime
            )
        }
    }

    private func recordValidation(
        _ result: AgentTraceEntry.Kind.ValidationInfo.Result,
        message: String,
        validator: String,
        sink: TurnTraceSink
    ) {
        sink.record(kind: .validation(.init(
            result: result,
            message: message,
            validator: validator
        )))
    }
}
