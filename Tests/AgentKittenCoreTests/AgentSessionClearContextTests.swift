// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore

@Test func clearContext_clearsStateByDefaultAndReplacesConversation() async throws {
    let provider = ScriptedInferenceProvider(
        responses: [
            .toolCall(
                name: "set_state",
                argumentsJSON: #"{"key":"topic","value":"Swift"}"#,
                thenRespond: "Saved."
            ),
            .success("Second"),
        ]
    )
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test(),
        sessionState: .enabledWithDefaultGuidance
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)
    #expect(await session.state.value(forKey: "topic") == "Swift")

    try await session.clearContext()
    #expect(await session.state.value(forKey: "topic") == nil)

    let secondTurn = try await session.send("Second")
    _ = try await collectEvents(from: secondTurn)

    let firstResolution = try #require(await conversationResolvedEntry(for: firstTurn.id, on: session))
    let secondResolution = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))
    let firstEntries = await directTurnEntries(for: firstTurn.id, on: session)
    let secondEntries = await directTurnEntries(for: secondTurn.id, on: session)

    #expect(firstResolution.identity.conversationID != secondResolution.identity.conversationID)
    #expect(secondResolution.resolutionKind == .replace)
    #expect(await provider.script.executionSessionUseCount() == 2)
    #expect(!firstEntries.isEmpty)
    #expect(!secondEntries.isEmpty)
}

@Test func clearContext_preserveStateKeepsScratchpadAndReplacesConversation() async throws {
    let provider = ScriptedInferenceProvider(
        responses: [
            .toolCall(
                name: "set_state",
                argumentsJSON: #"{"key":"topic","value":"Swift"}"#,
                thenRespond: "Saved."
            ),
            .success("Second"),
        ]
    )
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test(),
        sessionState: .enabledWithDefaultGuidance
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)

    try await session.clearContext(state: .preserve)

    let secondTurn = try await session.send("Second")
    _ = try await collectEvents(from: secondTurn)

    let firstResolution = try #require(await conversationResolvedEntry(for: firstTurn.id, on: session))
    let secondResolution = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))

    #expect(await session.state.value(forKey: "topic") == "Swift")
    #expect(firstResolution.identity.conversationID != secondResolution.identity.conversationID)
    #expect(secondResolution.resolutionKind == .replace)
}

@Test func clearContext_defaultClearsConversationWhenStateDisabled() async throws {
    let provider = ScriptedInferenceProvider(
        responses: [
            .success("First"),
            .success("Second"),
        ]
    )
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test()
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)

    // State is disabled; clearContext() should succeed as a no-op for state and clear the conversation.
    try await session.clearContext()

    let secondTurn = try await session.send("Second")
    _ = try await collectEvents(from: secondTurn)

    let firstResolution = try #require(await conversationResolvedEntry(for: firstTurn.id, on: session))
    let secondResolution = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))

    #expect(firstResolution.identity.conversationID != secondResolution.identity.conversationID)
    #expect(secondResolution.resolutionKind == .replace)
}

@Test func clearContext_defaultThrowsWhenStateReadOnlyWithoutReplacingConversation() async throws {
    let provider = ScriptedInferenceProvider(
        responses: [
            .success("First"),
            .success("Second"),
        ]
    )
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test(),
        sessionState: .readOnlyWithDefaultGuidance
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    _ = try await collectEvents(from: firstTurn)

    await #expect(throws: SessionStateError.readOnlyMutation) {
        try await session.clearContext()
    }

    let secondTurn = try await session.send("Second")
    _ = try await collectEvents(from: secondTurn)

    let firstResolution = try #require(await conversationResolvedEntry(for: firstTurn.id, on: session))
    let secondResolution = try #require(await conversationResolvedEntry(for: secondTurn.id, on: session))

    #expect(firstResolution.identity.conversationID == secondResolution.identity.conversationID)
    #expect(secondResolution.resolutionKind == .reuse)
}
