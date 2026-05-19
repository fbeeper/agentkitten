// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

private struct StructuredLabel: Codable, Sendable, JSONSchemaProviding, Equatable {
    let name: String
    let score: Double

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "name": .string(description: "The label name"),
                "score": .number(description: "The label score"),
            ],
            required: ["name", "score"],
        )
    }
}

private let emptyToolRuntime = testToolRuntime()

private struct StructuredEchoTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let message: String
    }

    struct Output: Codable, Sendable {
        let echo: String
    }

    static let name = "echo"
    static let defaultDescription = "Echoes the provided message."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["message": .string(description: "Message to echo.")],
            required: ["message"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(echo: arguments.message)
    }
}

@Suite("Conversation Structured")
struct ConversationStructuredTests {
    @Test func conversation_generateReturnsTypedValue() async throws {
        let json = #"{"name":"urgent","score":0.95}"#
        let conversation = Conversation(
            owner: .local,
            provider: MockInferenceProvider(
                responses: ["ignored"],
                structuredResponses: [json],
            ),
            systemPrompt: "You are a classifier.",
            executionConfiguration: EffectiveExecutionConfiguration(
                inferenceConfiguration: InferenceConfiguration(),
            ),
            toolRuntime: emptyToolRuntime,
        )

        let stream: AsyncThrowingStream<ConversationEvent<StructuredLabel>, Error> = try await conversation.generate(
            userMessage: UserMessage(text: "Classify this request"),
            executionConfiguration: EffectiveExecutionConfiguration(),
            toolExecutionContext: .empty,
        )
        let result = try await collectStructuredResult(from: stream)

        #expect(result == StructuredLabel(name: "urgent", score: 0.95))
    }

    @Test func conversation_generateFailsWhenStructuredGenerationFails() async throws {
        let conversation = Conversation(
            owner: .local,
            provider: MockInferenceProvider(responses: ["ignored"]),
            systemPrompt: "You are a classifier.",
            executionConfiguration: EffectiveExecutionConfiguration(
                inferenceConfiguration: InferenceConfiguration(),
            ),
            toolRuntime: emptyToolRuntime,
        )

        do {
            let stream: AsyncThrowingStream<ConversationEvent<StructuredLabel>, Error> =
                try await conversation.generate(
                    userMessage: UserMessage(text: "Classify this request"),
                    executionConfiguration: EffectiveExecutionConfiguration(),
                    toolExecutionContext: .empty,
                )
            let _: StructuredLabel = try await collectStructuredResult(from: stream)
            Issue.record("Expected structured generation to fail")
        } catch StructuredGenerationError.generationFailed {
            // Expected path.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func conversation_generateStreamsStructuredToolEvents() async throws {
        let json = #"{"name":"tool-backed","score":1}"#
        let conversation = Conversation(
            owner: .local,
            provider: MockInferenceProvider(
                responses: ["ignored"],
                structuredMockResponses: [
                    .toolCall(
                        name: "echo",
                        argumentsJSON: #"{"message":"tool-backed"}"#,
                        thenRespond: json,
                    ),
                ],
            ),
            systemPrompt: "You are a classifier.",
            executionConfiguration: EffectiveExecutionConfiguration(
                inferenceConfiguration: InferenceConfiguration(),
            ),
            toolRuntime: testToolRuntime(
                registry: ToolRegistry([AnyAgentTool(StructuredEchoTool())]),
            ),
        )

        let stream: AsyncThrowingStream<ConversationEvent<StructuredLabel>, Error> = try await conversation.generate(
            userMessage: UserMessage(text: "Classify this request"),
            executionConfiguration: EffectiveExecutionConfiguration(),
            toolExecutionContext: .empty,
        )
        let events = try await collectConversationEvents(from: stream)
        let result = try #require(events.compactMap { event -> StructuredLabel? in
            if case .result(let result) = event.kind {
                return result
            }
            return nil
        }.last)

        #expect(result == StructuredLabel(name: "tool-backed", score: 1))
        try assertStructuredToolFlow(
            events: events,
            expectedArgumentsJSON: #"{"message":"tool-backed"}"#,
            expectedSummary: .text(#"{"echo":"tool-backed"}"#),
        )
    }

    @Test func anyConversation_forwardsStructuredGeneration() async throws {
        let json = #"{"name":"forwarded","score":0.8}"#
        let anyConversation = AnyConversation(
            conversation: Conversation(
                owner: .local,
                provider: MockInferenceProvider(
                    responses: ["ignored"],
                    structuredResponses: [json],
                ),
                systemPrompt: "You are a classifier.",
                executionConfiguration: EffectiveExecutionConfiguration(
                    inferenceConfiguration: InferenceConfiguration(),
                ),
                toolRuntime: emptyToolRuntime,
            ),
        )

        let stream: AsyncThrowingStream<ConversationEvent<StructuredLabel>, Error> = try await anyConversation.generate(
            userMessage: UserMessage(text: "Classify this request"),
            executionConfiguration: EffectiveExecutionConfiguration(),
            toolExecutionContext: .empty,
        )
        let result = try await collectStructuredResult(from: stream)

        #expect(result == StructuredLabel(name: "forwarded", score: 0.8))
    }

    @Test func anyConversation_forwardsStructuredGenerationEvents() async throws {
        let json = #"{"name":"tool-forwarded","score":0.8}"#
        let anyConversation = AnyConversation(
            conversation: Conversation(
                owner: .local,
                provider: MockInferenceProvider(
                    responses: ["ignored"],
                    structuredMockResponses: [
                        .toolCall(
                            name: "echo",
                            argumentsJSON: #"{"message":"tool-forwarded"}"#,
                            thenRespond: json,
                        ),
                    ],
                ),
                systemPrompt: "You are a classifier.",
                executionConfiguration: EffectiveExecutionConfiguration(
                    inferenceConfiguration: InferenceConfiguration(),
                ),
                toolRuntime: testToolRuntime(
                    registry: ToolRegistry([AnyAgentTool(StructuredEchoTool())]),
                ),
            ),
        )

        let stream: AsyncThrowingStream<ConversationEvent<StructuredLabel>, Error> = try await anyConversation.generate(
            userMessage: UserMessage(text: "Classify this request"),
            executionConfiguration: EffectiveExecutionConfiguration(),
            toolExecutionContext: .empty,
        )
        let events = try await collectConversationEvents(from: stream)
        let result = try #require(events.compactMap { event -> StructuredLabel? in
            if case .result(let result) = event.kind {
                return result
            }
            return nil
        }.last)

        #expect(result == StructuredLabel(name: "tool-forwarded", score: 0.8))
        try assertStructuredToolFlow(
            events: events,
            expectedArgumentsJSON: #"{"message":"tool-forwarded"}"#,
            expectedSummary: .text(#"{"echo":"tool-forwarded"}"#),
        )
    }
}

private func collectConversationEvents<Result: Sendable>(
    from stream: AsyncThrowingStream<ConversationEvent<Result>, Error>,
) async throws -> [ConversationEvent<Result>] {
    var events: [ConversationEvent<Result>] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

private func collectStructuredResult<Result: Sendable>(
    from stream: AsyncThrowingStream<ConversationEvent<Result>, Error>,
) async throws -> Result {
    let events = try await collectConversationEvents(from: stream)
    return try #require(events.compactMap { event -> Result? in
        if case .result(let result) = event.kind {
            return result
        }
        return nil
    }.last)
}

private func firstToolCallStarted<Result: Sendable>(
    in events: [ConversationEvent<Result>],
) -> ConversationEvent<Result>? {
    events.first {
        if case .toolCallStarted = $0.kind {
            return true
        }
        return false
    }
}

private func firstToolCallCompleted<Result: Sendable>(
    in events: [ConversationEvent<Result>],
) -> ConversationEvent<Result>? {
    events.first {
        if case .toolCallCompleted = $0.kind {
            return true
        }
        return false
    }
}

private func assertStructuredToolFlow<Result: Sendable>(
    events: [ConversationEvent<Result>],
    expectedArgumentsJSON: String,
    expectedSummary: ToolResultContentSummary,
) throws {
    let started = try #require(firstToolCallStarted(in: events))
    let completed = try #require(firstToolCallCompleted(in: events))
    guard case .toolCallStarted(let name, _, let argumentsJSON) = started.kind else {
        Issue.record("Expected a structured tool call event")
        return
    }
    #expect(name == "echo")
    #expect(argumentsJSON == expectedArgumentsJSON)
    guard case .toolCallCompleted(let completedName, _, let outcome) = completed.kind else {
        Issue.record("Expected a structured tool result event")
        return
    }
    #expect(completedName == "echo")
    guard case .success(let content) = outcome else {
        Issue.record("Expected a successful structured tool result")
        return
    }
    #expect(content.map(\.summary) == [expectedSummary])
}
