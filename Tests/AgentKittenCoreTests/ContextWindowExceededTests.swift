// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore

@Test func contextWindowExceededFailsTurnWithTypedErrorAndQueueContinues() async throws {
    let overflow = InferenceError.contextWindowExceeded(.init(
        provider: "TestProvider",
        message: "context window exceeded",
        contextTokens: 101,
        contextSize: 100
    ))
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
            responses: [
                .failure(overflow),
                .success("Second response"),
            ],
        )),
        behavior: .test()
    )
    let session = agent.makeQueuedSession()

    let firstTurn = await session.send("first")
    let secondTurn = await session.send("second")

    do {
        _ = try await collectEvents(from: firstTurn)
        Issue.record("Expected first turn to fail with contextWindowExceeded")
    } catch let error as InferenceError {
        #expect(error == overflow)
    }

    let secondEvents = try await collectEvents(from: secondTurn)
    #expect(assistantCompletions(in: secondEvents) == ["Second response"])
    #expect(directTurnEntryKinds(in: await directTurnEntries(for: firstTurn.id, on: session.trace)) == [
        .turnStarted(UserMessage(text: "first")),
        .error(AgentTraceEntry.Kind.ErrorInfo(overflow)),
        .turnCompleted(.failed(AgentTraceEntry.Kind.ErrorInfo(overflow))),
    ])
}
