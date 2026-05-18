// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

private struct SessionStructuredLabel: Codable, Sendable, JSONSchemaProviding, Equatable {
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

@Suite("AgentSession Structured Generation")
struct AgentSessionStructuredTests {
    @Test func generate_returnsDecodedTypedResult() async throws {
        let json = #"{"name":"urgent","score":0.9}"#
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                structuredResponses: [.success(json)],
            )),
            behavior: .test("Classify the input."),
        )
        let session = agent.makeSession()

        let turn: Turn<SessionStructuredLabel> = try await session.generate("Classify: urgent request")
        let result = try await firstStructuredResult(from: turn)

        #expect(result == SessionStructuredLabel(name: "urgent", score: 0.9))
    }

    @Test func generate_emitsResultEventLast() async throws {
        let json = #"{"name":"low","score":0.1}"#
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                structuredResponses: [.success(json)],
            )),
            behavior: .test("Classify."),
        )
        let session = agent.makeSession()

        let turn: Turn<SessionStructuredLabel> = try await session.generate("go")
        let events = try await collectStructuredEvents(from: turn)

        let results = events.compactMap { event -> SessionStructuredLabel? in
            guard case .result(let value) = event.kind else {
                return nil
            }
            return value
        }
        #expect(results == [SessionStructuredLabel(name: "low", score: 0.1)])

        guard let last = events.last, case .result = last.kind else {
            Issue.record("Last event should be result")
            return
        }
    }

    @Test func generate_recordsStructuredResultInTrace() async throws {
        let json = #"{"name":"urgent","score":0.9}"#
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                structuredResponses: [.success(json)],
            )),
            behavior: .test("Classify."),
        )
        let session = agent.makeSession()

        let turn: Turn<SessionStructuredLabel> = try await session.generate("Classify input")
        _ = try await collectStructuredEvents(from: turn)

        let entries = await directTurnEntries(for: turn.id, on: session)
        let kinds = directTurnEntryKinds(in: entries)

        let expectedType = structuredResultTypeLabel(for: SessionStructuredLabel.self)
        let expectedJSON = try structuredResultJSON(for: SessionStructuredLabel(name: "urgent", score: 0.9))
        #expect(kinds.contains(.structuredResult(type: expectedType, json: expectedJSON)))
    }

    @Test func generate_returnsTopLevelArrayResult() async throws {
        let json = #"[{"name":"park","score":0.9},{"name":"museum","score":0.7}]"#
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                structuredResponses: [.success(json)],
            )),
            behavior: .test("Extract nearby places."),
        )
        let session = agent.makeSession()

        let turn: Turn<[SessionStructuredLabel]> = try await session.generate("List nearby places")
        let result = try await firstStructuredResult(from: turn)

        #expect(result == [
            SessionStructuredLabel(name: "park", score: 0.9),
            SessionStructuredLabel(name: "museum", score: 0.7),
        ])
    }

    @Test func generate_recordsTopLevelArrayResultInTrace() async throws {
        let json = #"[{"name":"park","score":0.9},{"name":"museum","score":0.7}]"#
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                structuredResponses: [.success(json)],
            )),
            behavior: .test("Extract nearby places."),
        )
        let session = agent.makeSession()

        let turn: Turn<[SessionStructuredLabel]> = try await session.generate("List nearby places")
        _ = try await collectStructuredEvents(from: turn)

        let entries = await directTurnEntries(for: turn.id, on: session)
        let kinds = directTurnEntryKinds(in: entries)
        let expectedType = structuredResultTypeLabel(for: [SessionStructuredLabel].self)
        let expectedJSON = try structuredResultJSON(for: [
            SessionStructuredLabel(name: "park", score: 0.9),
            SessionStructuredLabel(name: "museum", score: 0.7),
        ])
        #expect(kinds.contains(.structuredResult(type: expectedType, json: expectedJSON)))
    }

    @Test func generate_queuedAfterTextTurnCompletesInOrder() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [.success("Text response")],
            structuredResponses: [.success(#"{"name":"first","score":0.1}"#)],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test("Test."),
        )
        let session = agent.makeQueuedSession()

        let textTurn = await session.send("text")
        let structuredTurn: Turn<SessionStructuredLabel> = await session.generate("structured")

        let textResult = try await completedStructuredAssistantText(from: textTurn)
        let structuredResult = try await firstStructuredResult(from: structuredTurn)

        #expect(textResult == "Text response")
        #expect(structuredResult == SessionStructuredLabel(name: "first", score: 0.1))
    }

    @Test func generate_validationPass_emitsTypedResult() async throws {
        let json = #"{"name":"valid","score":0.8}"#
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                structuredResponses: [.success(json)],
            )),
            behavior: .test("Classify."),
        )
        let session = agent.makeSession()

        let turn: Turn<SessionStructuredLabel> = try await session.generate(
            "go",
            validation: ValidationConfiguration(
                validator: StructuredScoreThresholdValidator(minimumScore: 0.5),
            ),
        )
        let result = try await firstStructuredResult(from: turn)

        #expect(result == SessionStructuredLabel(name: "valid", score: 0.8))
    }

    @Test func generate_validationFeedback_retriesAndPassesOnSecondAttempt() async throws {
        let provider = ScriptedInferenceProvider(
            structuredResponses: [
                .success(#"{"name":"low","score":0.2}"#),
                .success(#"{"name":"high","score":0.9}"#),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test("Classify."),
        )
        let session = agent.makeSession()

        let turn: Turn<SessionStructuredLabel> = try await session.generate(
            "go",
            validation: ValidationConfiguration(
                validator: StructuredScoreThresholdValidator(minimumScore: 0.5),
                maxRetries: 1,
            ),
        )
        let result = try await firstStructuredResult(from: turn)

        #expect(result == SessionStructuredLabel(name: "high", score: 0.9))
        #expect(await provider.script.structuredSessionUseCount() == 1)
    }

    @Test func generate_validationExhaustion_permissiveReturnsLastAttempt() async throws {
        let provider = ScriptedInferenceProvider(
            structuredResponses: [
                .success(#"{"name":"low","score":0.2}"#),
                .success(#"{"name":"still-low","score":0.3}"#),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test("Classify."),
        )
        let session = agent.makeSession()

        let turn: Turn<SessionStructuredLabel> = try await session.generate(
            "go",
            validation: ValidationConfiguration(
                validator: StructuredScoreThresholdValidator(minimumScore: 0.5),
                maxRetries: 1,
                policy: .permissive,
            ),
        )
        let result = try await firstStructuredResult(from: turn)

        #expect(result == SessionStructuredLabel(name: "still-low", score: 0.3))
        #expect(await provider.script.structuredSessionUseCount() == 1)
        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "go")),
            .structuredResult(
                type: structuredResultTypeLabel(for: SessionStructuredLabel.self),
                json: try structuredResultJSON(for: SessionStructuredLabel(name: "low", score: 0.2)),
            ),
            .validation(.init(
                result: .feedback,
                message: "Score 0.2 is below minimum 0.5.",
                validator: "StructuredScoreThresholdValidator",
            )),
            .structuredResult(
                type: structuredResultTypeLabel(for: SessionStructuredLabel.self),
                json: try structuredResultJSON(for: SessionStructuredLabel(name: "still-low", score: 0.3)),
            ),
            .validation(.init(
                result: .feedback,
                message: "Score 0.3 is below minimum 0.5.",
                validator: "StructuredScoreThresholdValidator",
            )),
            .validation(.init(
                result: .waived,
                message: "Score 0.3 is below minimum 0.5.",
                validator: "StructuredScoreThresholdValidator",
            )),
            .turnCompleted(.completed),
        ])
    }
}

private struct StructuredScoreThresholdValidator: Validator {
    let minimumScore: Double

    func validate(_ context: ValidationContext<SessionStructuredLabel>) async throws -> ValidationResult {
        if context.result.score >= minimumScore {
            return .pass
        }
        return .feedback(message: "Score \(context.result.score) is below minimum \(minimumScore).")
    }
}

private func firstStructuredResult<Result>(from turn: Turn<Result>) async throws -> Result {
    var lastResult: Result?
    for try await event in turn.events {
        if case .result(let value) = event.kind {
            lastResult = value
        }
    }
    return try #require(lastResult, "Expected a result event")
}

private func collectStructuredEvents<Result>(
    from turn: Turn<Result>,
) async throws -> [AgentEvent<Result>] {
    var events: [AgentEvent<Result>] = []
    for try await event in turn.events {
        events.append(event)
    }
    return events
}

private func completedStructuredAssistantText(
    from turn: Turn<AssistantMessage>,
) async throws -> String {
    var lastText: String?
    for try await event in turn.events {
        if case .result(let assistant) = event.kind {
            lastText = assistant.text
        }
    }
    return try #require(lastText, "Expected an assistant result event")
}
