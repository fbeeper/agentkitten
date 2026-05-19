// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Suite("Validation Policy")
struct ValidationPolicyTests {
    @Test func validatorFailure_recordsValidationAndFailsTurn() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [.success("Will fail validation")],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello", validation: ValidationConfiguration(
            validator: TerminalFailureValidator(reason: "Terminal validation failure"),
        ))
        await #expect(throws: Error.self) {
            _ = try await collectEvents(from: turn)
        }

        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "Will fail validation"))),
            .validation(.init(
                result: .fail,
                message: "Terminal validation failure",
                validator: "TerminalFailureValidator",
            )),
            .error(.init(description: "rejected(\"Terminal validation failure\")")),
            .turnCompleted(.failed(.init(description: "rejected(\"Terminal validation failure\")"))),
        ])
    }

    @Test func validationExhaustion_passThroughReturnsLastAttempt() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [
                .success("bad"),
                .success("worse"),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello", validation: ValidationConfiguration(
            validator: MinimumLengthValidator(minimumLength: 10),
            maxRetries: 1,
            policy: .permissive,
        ))
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["worse"])
        #expect(await provider.script.executionSessionUseCount() == 1)
        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "bad"))),
            .validation(.init(
                result: .feedback,
                message: "Response must be at least 10 characters.",
                validator: "MinimumLengthValidator(10)",
            )),
            .message(.assistant(AssistantMessage(text: "worse"))),
            .validation(.init(
                result: .feedback,
                message: "Response must be at least 10 characters.",
                validator: "MinimumLengthValidator(10)",
            )),
            .validation(.init(
                result: .waived,
                message: "Response must be at least 10 characters.",
                validator: "MinimumLengthValidator(10)",
            )),
            .turnCompleted(.completed),
        ])
    }

    @Test func validationFailure_passThroughReturnsLastAttempt() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [.success("still returned")],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello", validation: ValidationConfiguration(
            validator: ThrowingValidator(message: "validator unavailable"),
            policy: .permissive,
        ))
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["still returned"])
        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "still returned"))),
            .validation(.init(
                result: .waived,
                message: "validator unavailable",
                validator: "ThrowingValidator",
            )),
            .turnCompleted(.completed),
        ])
    }

    @Test func validationExhaustion_failFailsTurn() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [
                .success("bad"),
                .success("tiny"),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello", validation: ValidationConfiguration(
            validator: MinimumLengthValidator(minimumLength: 10),
            maxRetries: 1,
            policy: .restrictive,
        ))
        await #expect(throws: Error.self) {
            _ = try await collectEvents(from: turn)
        }

        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "bad"))),
            .validation(.init(
                result: .feedback,
                message: "Response must be at least 10 characters.",
                validator: "MinimumLengthValidator(10)",
            )),
            .message(.assistant(AssistantMessage(text: "tiny"))),
            .validation(.init(
                result: .feedback,
                message: "Response must be at least 10 characters.",
                validator: "MinimumLengthValidator(10)",
            )),
            .validation(.init(
                result: .fail,
                message: "Response must be at least 10 characters.",
                validator: "MinimumLengthValidator(10)",
            )),
            .error(.init(description: "failed(\"Response must be at least 10 characters.\")")),
            .turnCompleted(.failed(.init(
                description: "failed(\"Response must be at least 10 characters.\")",
            ))),
        ])
    }

    @Test func traceNames_distinguishParameterizedValidatorsOfSameType() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [.success("just enough")],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let validation = ValidationConfiguration(
            validator: MinimumLengthValidator(minimumLength: 4),
        ).adding(MinimumLengthValidator(minimumLength: 20))

        let turn = try await session.send("Hello", validation: validation)
        await #expect(throws: Error.self) {
            _ = try await collectEvents(from: turn)
        }

        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "just enough"))),
            .validation(.init(
                result: .pass,
                message: "Validation passed.",
                validator: "MinimumLengthValidator(4)",
            )),
            .validation(.init(
                result: .feedback,
                message: "Response must be at least 20 characters.",
                validator: "MinimumLengthValidator(20)",
            )),
            .validation(.init(
                result: .fail,
                message: "Response must be at least 20 characters.",
                validator: "MinimumLengthValidator(20)",
            )),
            .error(.init(description: "failed(\"Response must be at least 20 characters.\")")),
            .turnCompleted(.failed(.init(
                description: "failed(\"Response must be at least 20 characters.\")",
            ))),
        ])
    }
}
