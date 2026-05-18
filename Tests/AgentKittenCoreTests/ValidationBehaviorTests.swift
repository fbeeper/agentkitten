// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Suite("Validation Behavior")
struct ValidationBehaviorTests {
    @Test func disabledValidationConfiguration_behavesLikeNoValidation() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [.success("Unvalidated response")],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello", validation: .disabled)
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["Unvalidated response"])
        #expect(events.contains { if case .textDelta = $0.kind { return true }; return false })
        #expect(await provider.script.executionSessionUseCount() == 1)
        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "Unvalidated response"))),
            .turnCompleted(.completed),
        ])
    }

    @Test func validatorsPass_streamsAssistantNormally() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [.success("Long enough response")],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello", validation: ValidationConfiguration(
            validator: MinimumLengthValidator(minimumLength: 8),
        ))
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["Long enough response"])
        #expect(events.allSatisfy { if case .textDelta = $0.kind { return false }; return true })
        #expect(await provider.script.executionSessionUseCount() == 1)
        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "Long enough response"))),
            .validation(.init(
                result: .pass,
                message: AgentKittenLocalization.string("validation.validationPassed"),
                validator: "MinimumLengthValidator(8)",
            )),
            .turnCompleted(.completed),
        ])
    }

    @Test func feedbackRetry_reusesConversationAndOnlyStreamsAcceptedAssistant() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [
                .success("bad"),
                .success("Accepted revision"),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello", validation: ValidationConfiguration(
            validator: MinimumLengthValidator(minimumLength: 8),
            maxRetries: 1,
        ))
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["Accepted revision"])
        #expect(await provider.script.executionSessionUseCount() == 1)
        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "bad"))),
            .validation(.init(
                result: .feedback,
                message: "Response must be at least 8 characters.",
                validator: "MinimumLengthValidator(8)",
            )),
            .message(.assistant(AssistantMessage(text: "Accepted revision"))),
            .validation(.init(
                result: .pass,
                message: AgentKittenLocalization.string("validation.validationPassed"),
                validator: "MinimumLengthValidator(8)",
            )),
            .turnCompleted(.completed),
        ])
    }

    @Test func validatorOrdering_stopsOnFirstNonPass() async throws {
        let recorder = ValidationRecorder()
        let provider = ScriptedInferenceProvider(
            responses: [.success("bad")],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let validation = ValidationConfiguration(
            validator: OrderedValidator(
                result: .feedback(message: "Need more"),
                recorder: recorder,
                label: "first",
            ),
            policy: .permissive,
        ).adding(
            OrderedValidator(
                result: .pass,
                recorder: recorder,
                label: "second",
            ),
        )
        let turn = try await session.send("Hello", validation: validation)
        _ = try await collectEvents(from: turn)

        #expect(await recorder.recordedLabels() == ["first"])
    }

    @Test func defaultRetryFeedbackMessage_hidesValidationMechanicsFromUserAnswer() {
        let message = ValidationConfiguration<AssistantMessage>.defaultRetryFeedbackMessage(
            "Add more detail.",
        )

        #expect(message.text.contains("Add more detail."))
        #expect(message.text.contains("Do not mention validation"))
        #expect(message.text.contains("Present the revised answer directly"))
        #expect(message.text.contains("as if it were your first response"))
        #expect(message.text.contains("Apply this feedback only to the current response"))
        #expect(message.text.contains("Do not carry this feedback forward into future turns"))
    }
}
