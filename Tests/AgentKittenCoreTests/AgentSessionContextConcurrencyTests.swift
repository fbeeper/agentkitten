// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Test func contextOperations_throwBusyDuringActiveTurn() async throws {
    let provider = GateInferenceProvider()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let turn = try await session.send("First")
    let turnTask = Task { try await collectEvents(from: turn) }
    await provider.waitUntilStarted("First")

    await #expect(throws: AgentSessionError.concurrentOperationInProgress(active: .run)) {
        _ = try await session.contextUsage()
    }
    await #expect(throws: AgentSessionError.concurrentOperationInProgress(active: .run)) {
        _ = try await session.compactContext()
    }
    await #expect(throws: AgentSessionError.concurrentOperationInProgress(active: .run)) {
        try await session.clearContext(state: .preserve)
    }

    await provider.release("First")
    _ = try await turnTask.value
}

@Test func clearContext_reentersAfterActiveTurnFullyFinishes() async throws {
    let provider = GateInferenceProvider()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let firstTurn = try await session.send("First")
    let firstTask = Task { try await collectEvents(from: firstTurn) }
    await provider.waitUntilStarted("First")

    await #expect(throws: AgentSessionError.concurrentOperationInProgress(active: .run)) {
        try await session.clearContext(state: .preserve)
    }

    await provider.release("First")
    _ = try await firstTask.value

    try await session.clearContext(state: .preserve)

    let secondTurn = try await session.send("Second")
    let secondTask = Task { try await collectEvents(from: secondTurn) }
    await provider.waitUntilStarted("Second")
    await provider.release("Second")
    _ = try await secondTask.value
}
