// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

// MARK: - Helpers

private func makeConversation(
    responses: [String] = ["Hello"],
    structuredResponses: [String] = [],
) -> Conversation<MockInferenceProvider> {
    let provider = MockInferenceProvider(
        responses: responses,
        structuredResponses: structuredResponses,
    )
    return Conversation(
        owner: .local,
        provider: provider,
        systemPrompt: "Test",
        executionConfiguration: EffectiveExecutionConfiguration(),
        toolRuntime: testToolRuntime(),
    )
}

private func sendStream(
    _ conversation: Conversation<MockInferenceProvider>,
) async throws -> AsyncThrowingStream<ConversationEvent<AssistantMessage>, Error> {
    try await conversation.send(
        userMessage: UserMessage(text: "Hi"),
        executionConfiguration: EffectiveExecutionConfiguration(),
        toolExecutionContext: .empty,
    )
}

// MARK: - Sequential sends

@Test func conversation_allowsSequentialSends() async throws {
    let conversation = makeConversation(responses: ["First", "Second"])

    var first = ""
    for try await event in try await sendStream(conversation) {
        if case .textDelta(let chunk) = event.kind {
            first += chunk
        }
    }

    var second = ""
    for try await event in try await sendStream(conversation) {
        if case .textDelta(let chunk) = event.kind {
            second += chunk
        }
    }

    #expect(first == "First")
    #expect(second == "Second")
}

// MARK: - Concurrent rejection

@Test func conversation_rejectsConcurrentSend() async throws {
    let conversation = makeConversation(responses: ["First", "Second"])

    // Hold the stream without consuming it — onTermination has not fired,
    // so the gate is still held.
    let stream1 = try await sendStream(conversation)

    await #expect(throws: InferenceError.concurrentOperationInProgress(active: .run)) {
        _ = try await sendStream(conversation)
    }

    // Drain stream1 to release the gate.
    for try await _ in stream1 {}

    // Now a follow-up send must succeed.
    var second = ""
    for try await event in try await sendStream(conversation) {
        if case .textDelta(let chunk) = event.kind {
            second += chunk
        }
    }
    #expect(second == "Second")
}

@Test func conversation_rejectsContextUsageDuringSend() async throws {
    let conversation = makeConversation()

    let stream = try await sendStream(conversation)

    await #expect(throws: InferenceError.concurrentOperationInProgress(active: .run)) {
        _ = try await conversation.contextUsage()
    }

    for try await _ in stream {}

    // Gate released — contextUsage now succeeds.
    _ = try await conversation.contextUsage()
}

@Test func conversation_rejectsCompactContextDuringSend() async throws {
    let conversation = makeConversation()

    let stream = try await sendStream(conversation)

    await #expect(throws: InferenceError.concurrentOperationInProgress(active: .run)) {
        _ = try await conversation.compactContext(
            options: ContextCompactionOptions(),
            summaryGenerator: { _ in "summary" },
        )
    }

    for try await _ in stream {}
}
