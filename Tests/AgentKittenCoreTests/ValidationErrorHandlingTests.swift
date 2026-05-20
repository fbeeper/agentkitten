// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Suite("Validation Error Handling")
struct ValidationErrorHandlingTests {
    @Test func validationError_retriesValidationWithoutRegenerating() async throws {
        let recorder = FlakyValidationRecorder()
        let provider = ScriptedInferenceProvider(
            responses: [.success("stable response")],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello", validation: ValidationConfiguration(
            validator: FlakyValidator(
                recorder: recorder,
                errorMessage: "validator unavailable",
            ),
            maxRetries: 1,
        ))
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["stable response"])
        #expect(await recorder.attempts() == 2)
        #expect(await provider.script.executionSessionUseCount() == 1)
        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "stable response"))),
            .validation(AgentTraceEntry.Kind.ValidationInfo(
                result: .pass,
                message: "Validation passed.",
                validator: "FlakyValidator",
            )),
            .turnCompleted(.completed),
        ])
    }
}
