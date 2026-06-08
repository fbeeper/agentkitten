// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import AgentKittenInferenceTestSupport
import Testing

@Test func mockSession_allowsFollowUpRunAfterFirstStreamFullyTerminates() async throws {
    let provider = MockInferenceProvider(responses: ["First", "Second"])
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        toolSelection: .all,
        inferenceContext: .empty,
    )
    let message = UserMessage(text: "Hi")

    var first = ""
    for try await event in try await session.run(message, parameters: InferenceRequestParameters()) {
        if case .delta(let chunk) = event {
            first += chunk
        }
    }

    var second = ""
    for try await event in try await session.run(message, parameters: InferenceRequestParameters()) {
        if case .delta(let chunk) = event {
            second += chunk
        }
    }

    #expect(first == "First")
    #expect(second == "Second")
}

@Test func mockSession_cancellingStreamReleasesOperationGate() async throws {
    let provider = MockInferenceProvider(responses: ["First response", "Second response"])
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        toolSelection: .all,
        inferenceContext: .empty,
    )

    do {
        let stream = try await session.run(UserMessage(text: "Hi"), parameters: InferenceRequestParameters())
        let consumeOneEvent = Task {
            for try await _ in stream {
                break
            }
        }
        try await consumeOneEvent.value
    }

    var second = ""
    for try await event in try await session.run(UserMessage(text: "Again"), parameters: InferenceRequestParameters()) {
        if case .delta(let chunk) = event {
            second += chunk
        }
    }

    #expect(second == "Second response")
}

@Test func mockSession_allowsFollowUpStructuredGenerationAfterFirstStreamTerminates() async throws {
    let provider = MockInferenceProvider(
        responses: ["Hello world"],
        structuredResponses: [
            #"{"label":"first"}"#,
            #"{"label":"second"}"#,
        ],
    )
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
        toolSelection: .all,
        inferenceContext: .empty,
    )

    let first: MockStructuredValue = try await session.generate(
        prompt: "Return the first label",
        parameters: InferenceRequestParameters(),
    )
    let second: MockStructuredValue = try await session.generate(
        prompt: "Return the second label",
        parameters: InferenceRequestParameters(),
    )

    #expect(first == MockStructuredValue(label: "first"))
    #expect(second == MockStructuredValue(label: "second"))
}
