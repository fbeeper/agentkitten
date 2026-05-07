// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore

@Test func stateMutationsStayAttributedToTheirOwnTurnsAcrossBackToBackTurns() async throws {
    let provider = ScriptedInferenceProvider(responses: [
        .toolCall(
            name: "set_state",
            argumentsJSON: #"{"key":"topic","value":"Swift"}"#,
            thenRespond: "Saved Swift."
        ),
        .toolCall(
            name: "set_state",
            argumentsJSON: #"{"key":"tone","value":"Direct"}"#,
            thenRespond: "Saved Direct."
        ),
    ])
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test(),
        sessionState: .enabledWithDefaultGuidance
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("Remember topic")
    _ = try await collectEvents(from: firstTurn)
    let secondTurn = try await session.send("Remember tone")
    _ = try await collectEvents(from: secondTurn)

    let firstMutations = await directTurnEntries(for: firstTurn.id, on: session).compactMap { entry in
        if case .stateMutation(let mutation) = entry.kind {
            return mutation
        }
        return nil
    }
    let secondMutations = await directTurnEntries(for: secondTurn.id, on: session).compactMap { entry in
        if case .stateMutation(let mutation) = entry.kind {
            return mutation
        }
        return nil
    }

    #expect(firstMutations.count == 1)
    #expect(firstMutations.first?.operation == .set)
    #expect(firstMutations.first?.key == "topic")
    #expect(firstMutations.first?.valueType == "string")

    #expect(secondMutations.count == 1)
    #expect(secondMutations.first?.operation == .set)
    #expect(secondMutations.first?.key == "tone")
    #expect(secondMutations.first?.valueType == "string")
}
