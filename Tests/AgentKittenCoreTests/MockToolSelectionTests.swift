// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import AgentKittenInferenceTestSupport
import Testing

@Test func mockSession_excludedToolSelectionDeniesToolWithoutExecuting() async throws {
    let counter = ToolCallCounter()
    let session = makeCountingEchoMockSession(
        responses: [
            .toolCall(
                name: "counting_echo",
                argumentsJSON: #"{"message":"blocked"}"#,
                thenRespond: "Done.",
            ),
        ],
        counter: counter,
    )

    var outcome: ToolCallOutcome?
    for try await event in try await session.run(
        UserMessage(text: "Hi"),
        parameters: InferenceRequestParameters(toolSelection: .excluding(["counting_echo"])),
    ) {
        if case .toolCallCompleted(_, _, let completed) = event {
            outcome = completed
        }
    }

    let expectedReason = "tool unavailable: counting_echo"
    #expect(outcome == .failure(.denied(reason: expectedReason)))
    #expect(await counter.value() == 0)
}

@Test func mockSession_includedToolSelectionExecutesMatchingTool() async throws {
    let counter = ToolCallCounter()
    let session = makeCountingEchoMockSession(
        responses: [
            .toolCall(
                name: "counting_echo",
                argumentsJSON: #"{"message":"allowed"}"#,
                thenRespond: "Done.",
            ),
        ],
        counter: counter,
    )

    var outcome: ToolCallOutcome?
    for try await event in try await session.run(
        UserMessage(text: "Hi"),
        parameters: InferenceRequestParameters(toolSelection: .including(["counting_echo"])),
    ) {
        if case .toolCallCompleted(_, _, let completed) = event {
            outcome = completed
        }
    }

    #expect(await counter.value() == 1)
    if case .success = outcome {
        return
    }
    Issue.record("Expected the included tool to execute successfully.")
}

@Test func mockSession_includingSelectionDeniesUnlistedStructuredTool() async throws {
    let counter = ToolCallCounter()
    let session = makeCountingEchoMockSession(
        responses: [.success("Hello world")],
        structuredResponses: [
            .toolCall(
                name: "counting_echo",
                argumentsJSON: #"{"message":"blocked"}"#,
                thenRespond: #"{"label":"structured"}"#,
            ),
        ],
        counter: counter,
    )

    let stream: StructuredInferenceStream<SelectionStructuredValue> =
        try await session.generateStream(
            prompt: "Return a label",
            parameters: InferenceRequestParameters(toolSelection: .including(["other_tool"])),
        )

    var outcome: ToolCallOutcome?
    for try await event in stream {
        if case .toolCallCompleted(_, _, let completed) = event {
            outcome = completed
        }
    }

    let expectedReason = "tool unavailable: counting_echo"
    #expect(outcome == .failure(.denied(reason: expectedReason)))
    #expect(await counter.value() == 0)
}

private func makeCountingEchoMockSession(
    responses: [MockResponse],
    structuredResponses: [MockResponse] = [],
    counter: ToolCallCounter,
) -> MockInferenceSession {
    let provider = MockInferenceProvider(
        mockResponses: responses,
        structuredMockResponses: structuredResponses,
    )
    let registry = ToolRegistry([AnyAgentTool(CountingEchoTool(counter: counter))])
    return provider.makeSession(
        systemPrompt: nil,
        toolRuntime: testToolRuntime(registry: registry),
        toolSelection: .all,
    )
}

private struct SelectionStructuredValue: Codable, Sendable, JSONSchemaProviding, Equatable {
    let label: String

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "label": .string(description: "The generated label"),
            ],
            required: ["label"],
        )
    }
}
