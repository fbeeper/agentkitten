// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore

@Test func turnNote_prependsToUserMessage_turnCompletes() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider(responses: ["ok"])),
        behavior: .test("You are helpful.")
    )
    let session = agent.makeSession()
    let turn = try await session.send("hello", turnOverrides: TurnOverrides(turnNote: "Plan mode is active."))
    var resultText: String?
    for try await event in turn.events {
        if case .result(let msg) = event.kind {
            resultText = msg.text
        }
    }
    #expect(resultText != nil)
}

@Test func turnNote_nil_turnCompletes() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MockInferenceProvider(responses: ["ok"])),
        behavior: .test("You are helpful.")
    )
    let session = agent.makeSession()
    let turn = try await session.send("hello")
    var resultText: String?
    for try await event in turn.events {
        if case .result(let msg) = event.kind {
            resultText = msg.text
        }
    }
    #expect(resultText != nil)
}
