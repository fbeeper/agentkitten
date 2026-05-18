// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

private struct JudgeLabel: Codable, Sendable, JSONSchemaProviding, Equatable {
    let name: String
    let score: Double

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "name": .string(description: "The label name"),
                "score": .number(description: "The confidence score"),
            ],
            required: ["name", "score"],
        )
    }
}

@Suite("Judge Validator")
struct JudgeValidatorTests {
    @Test func judgeValidator_passesAndRecordsConfiguredName() async throws {
        let outerProvider = ScriptedInferenceProvider(
            responses: [.success("Candidate response")],
        )
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [.success(#"{"verdict":"pass"}"#)],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: outerProvider),
            behavior: .test("Answer the user."),
        )
        let session = agent.makeSession()

        let turn = try await session.send(
            "Hi",
            validation: ValidationConfiguration(
                validator: JudgeValidator<AssistantMessage>(
                    prompt: .criteria("The response must be acceptable."),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                    name: "Policy Judge",
                ),
            ),
        )
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["Candidate response"])
        #expect(await judgeProvider.script.structuredSessionUseCount() == 1)
        #expect(
            await judgeProvider.script.latestPrompt()?
                .contains("The response must be acceptable.") == true,
        )
        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hi")),
            .message(.assistant(AssistantMessage(text: "Candidate response"))),
            .validation(.init(
                result: .pass,
                message: AgentKittenLocalization.string("validation.validationPassed"),
                validator: "Policy Judge",
            )),
            .turnCompleted(.completed),
        ])
    }

    @Test func judgeValidator_feedbackRetriesWithFreshJudgeSession() async throws {
        let outerProvider = ScriptedInferenceProvider(
            responses: [
                .success("First attempt"),
                .success("Second attempt"),
            ],
        )
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [
                .success(#"{"verdict":"feedback","message":"Try again with more detail."}"#),
                .success(#"{"verdict":"pass"}"#),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: outerProvider),
            behavior: .test("Answer the user."),
        )
        let session = agent.makeSession()

        let turn = try await session.send(
            "Hi",
            validation: ValidationConfiguration(
                validator: JudgeValidator<AssistantMessage>(
                    prompt: .criteria("The response must be detailed."),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                ),
                maxRetries: 1,
            ),
        )
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["Second attempt"])
        #expect(await judgeProvider.script.structuredSessionUseCount() == 2)
    }

    @Test func judgeValidator_failRejectsTurn() async throws {
        let outerProvider = ScriptedInferenceProvider(
            responses: [.success("Candidate response")],
        )
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [
                .success(#"{"verdict":"fail","message":"The response is unacceptable."}"#),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: outerProvider),
            behavior: .test("Answer the user."),
        )
        let session = agent.makeSession()

        let turn = try await session.send(
            "Hi",
            validation: ValidationConfiguration(
                validator: JudgeValidator<AssistantMessage>(
                    prompt: .criteria("The response must be acceptable."),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                    name: "Rejecting Judge",
                ),
            ),
        )
        await #expect(throws: Error.self) {
            _ = try await collectEvents(from: turn)
        }

        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Hi")),
            .message(.assistant(AssistantMessage(text: "Candidate response"))),
            .validation(.init(
                result: .fail,
                message: "The response is unacceptable.",
                validator: "Rejecting Judge",
            )),
            .error(.init(description: "rejected(\"The response is unacceptable.\")")),
            .turnCompleted(.failed(.init(
                description: "rejected(\"The response is unacceptable.\")",
            ))),
        ])
    }

    @Test func judgeValidator_errorUsesValidationPolicy() async throws {
        let outerProvider = ScriptedInferenceProvider(
            responses: [.success("Candidate response")],
        )
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [.failure(.invalidResponse("offline"))],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: outerProvider),
            behavior: .test("Answer the user."),
        )
        let session = agent.makeSession()

        let turn = try await session.send(
            "Hi",
            validation: ValidationConfiguration(
                validator: JudgeValidator<AssistantMessage>(
                    prompt: .criteria("The response must be acceptable."),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                    name: "Offline Judge",
                ),
                policy: .permissive,
            ),
        )
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["Candidate response"])
        let kinds = directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session))
        let info = try requiredValidationInfo(
            in: kinds,
            validator: "Offline Judge",
            result: .waived,
        )
        #expect(info.message.contains("generationFailed"))
        #expect(info.message.contains("invalidResponse"))
        #expect(info.message.contains("offline"))
    }

    @Test func judgeValidator_defaultHasNoTools() async throws {
        let counter = ToolCallCounter()
        let outerProvider = ScriptedInferenceProvider(
            responses: [.success("Candidate response")],
        )
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [
                .toolCall(
                    name: CountingEchoTool.name,
                    argumentsJSON: #"{"message":"hi"}"#,
                    thenRespond: #"{"verdict":"pass"}"#,
                ),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: outerProvider),
            behavior: .test("Answer the user."),
        )
        let session = agent.makeSession()

        let turn = try await session.send(
            "Hi",
            validation: ValidationConfiguration(
                validator: JudgeValidator<AssistantMessage>(
                    prompt: .criteria("The response must be acceptable."),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                ),
            ),
        )
        await #expect(throws: Error.self) {
            _ = try await collectEvents(from: turn)
        }

        #expect(await counter.value() == 0)
    }

    @Test func judgeValidator_optionalToolsCanBeUsed() async throws {
        let counter = ToolCallCounter()
        let outerProvider = ScriptedInferenceProvider(
            responses: [.success("Candidate response")],
        )
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [
                .toolCall(
                    name: CountingEchoTool.name,
                    argumentsJSON: #"{"message":"hi"}"#,
                    thenRespond: #"{"verdict":"pass"}"#,
                ),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: outerProvider),
            behavior: .test("Answer the user."),
        )
        let session = agent.makeSession()

        let turn = try await session.send(
            "Hi",
            validation: ValidationConfiguration(
                validator: JudgeValidator<AssistantMessage>(
                    prompt: .criteria("The response must be acceptable."),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                    toolDefinition: ToolDefinition(
                        tools: [AnyAgentTool(CountingEchoTool(counter: counter))],
                    ),
                ),
            ),
        )
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["Candidate response"])
        #expect(await counter.value() == 1)
        #expect(
            await judgeProvider.script.latestStructuredUserPrompt()?
                .contains("Candidate result:") == true,
        )
    }
}

@Suite("Judge Validator State Access")
struct JudgeValidatorStateAccessTests {
    @Test func judgeValidator_validatesStructuredResults() async throws {
        let resultJSON = #"{"name":"urgent","score":0.9}"#
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [.success(#"{"verdict":"pass"}"#)],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                structuredResponses: [.success(resultJSON)],
            )),
            behavior: .test("Classify."),
        )
        let session = agent.makeSession()

        let turn: Turn<JudgeLabel> = try await session.generate(
            "Classify",
            validation: ValidationConfiguration(
                validator: JudgeValidator<JudgeLabel>(
                    prompt: .criteria("The label must be valid."),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                    name: "Structured Judge",
                ),
            ),
        )
        let result = try await firstStructuredResult(from: turn)

        #expect(result == JudgeLabel(name: "urgent", score: 0.9))
        #expect(
            await judgeProvider.script.latestStructuredUserPrompt()?
                .contains(#"{"name":"urgent","score":0.9}"#) == true,
        )
    }

    @Test func judgeValidator_canReadOuterSessionStateThroughReadOnlyTools() async throws {
        let outerProvider = ScriptedInferenceProvider(
            responses: [
                .toolCall(
                    name: "set_state",
                    argumentsJSON: #"{"key":"topic","value":"Swift"}"#,
                    thenRespond: "Saved.",
                ),
                .success("Candidate response"),
            ],
        )
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [
                .toolCall(
                    name: "get_state",
                    argumentsJSON: #"{"key":"topic"}"#,
                    thenRespond: #"{"verdict":"pass"}"#,
                ),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: outerProvider),
            behavior: .test("Answer the user."),
            sessionState: .enabledWithDefaultGuidance,
        )
        let session = agent.makeSession()

        let rememberTurn = try await session.send("Remember topic")
        _ = try await collectEvents(from: rememberTurn)
        #expect(await session.state.value(forKey: "topic") == "Swift")

        let turn = try await session.send(
            "Hi",
            validation: ValidationConfiguration(
                validator: JudgeValidator<AssistantMessage>(
                    prompt: .criteria("Check the saved topic before approving the response."),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                    sessionStateAccess: .readOnlyTools,
                ),
            ),
        )
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["Candidate response"])
        #expect(await session.state.value(forKey: "topic") == "Swift")
        #expect(
            await judgeProvider.script.latestPrompt()?
                .contains("Session state is read-only in this session.") == true,
        )
    }
}

private func firstStructuredResult<T: Sendable>(
    from turn: Turn<T>,
) async throws -> T {
    for try await event in turn.events {
        if case .result(let result) = event.kind {
            return result
        }
    }
    throw JudgeValidatorTestError.missingResult
}

private enum JudgeValidatorTestError: Error {
    case missingResult
    case missingValidationInfo
}

private func requiredValidationInfo(
    in kinds: [AgentTraceEntry.Kind],
    validator: String,
    result: AgentTraceEntry.Kind.ValidationInfo.Result,
) throws -> AgentTraceEntry.Kind.ValidationInfo {
    for kind in kinds {
        guard case .validation(let info) = kind else {
            continue
        }
        if info.validator == validator, info.result == result {
            return info
        }
    }
    throw JudgeValidatorTestError.missingValidationInfo
}
