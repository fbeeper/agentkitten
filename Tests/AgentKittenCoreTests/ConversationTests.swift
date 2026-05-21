// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Test func multiTurn() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [
            .success("First response"),
            .success("Second response"),
        ])),
        behavior: .test("You are helpful"),
    )
    let session = agent.makeQueuedSession()

    let first = try await completedAssistantText(from: await session.send("Hello"))
    let second = try await completedAssistantText(from: await session.send("World"))

    #expect(first == "First response")
    #expect(second == "Second response")
}

@Test func streamEvents() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [.success("Hello world")])),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let events = try await collectedEvents(from: try await session.send("Hi"))

    let deltas = events.filter { if case .textDelta = $0.kind { return true }; return false }
    #expect(!deltas.isEmpty)

    let completionTexts = events.compactMap { event -> String? in
        guard case .result(let assistant) = event.kind else {
            return nil
        }
        return assistant.text
    }
    #expect(completionTexts == ["Hello world"])

    guard let last = events.last, case .result = last.kind else {
        Issue.record("Last event should be result")
        return
    }
}

@Test func concurrentTurnStartFailsFast() async throws {
    let provider = GateInferenceProvider()
    let conversation = Conversation(
        owner: .local,
        provider: provider,
        systemPrompt: "Test",
        executionConfiguration: EffectiveExecutionConfiguration(),
        toolRuntime: testToolRuntime(),
    )

    let firstStream = try await conversation.send(
        userMessage: UserMessage(text: "a1"),
        executionConfiguration: EffectiveExecutionConfiguration(),
        toolExecutionContext: .empty,
    )
    let firstTask = Task {
        for try await _ in firstStream {}
    }
    await provider.waitUntilStarted("a1")

    await #expect(throws: InferenceError.concurrentOperationInProgress(active: .run)) {
        _ = try await conversation.send(
            userMessage: UserMessage(text: "a2"),
            executionConfiguration: EffectiveExecutionConfiguration(),
            toolExecutionContext: .empty,
        )
    }

    await provider.release("a1")
    _ = try await firstTask.value
}

@Test func turnEventIteratorRetainsTurnForInlineConsumption() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
            responses: [.success("Inline response")],
        )),
        behavior: .test(),
    )
    let session = agent.makeSession()

    weak var turnWitness: Turn<AssistantMessage>?
    var iterator: TurnEventStream<AssistantMessage>.AsyncIterator?

    do {
        let turn = try await session.send("Hi")
        turnWitness = turn
        iterator = turn.events.makeAsyncIterator()
    }

    #expect(turnWitness != nil)

    var completions: [String] = []
    while let event = try await iterator?.next() {
        if case .result(let assistant) = event.kind {
            completions.append(assistant.text)
        }
    }

    #expect(completions == ["Inline response"])

    iterator = nil
    await Task.yield()
    #expect(turnWitness == nil)
}

@Test func cancellationNoCorruption() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [
            .success("Cancel this now"),
            .success("Safe response"),
        ])),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let turn1 = try await session.send("first")
    for try await event in turn1.events {
        if case .textDelta = event.kind {
            await turn1.cancel()
            #if os(WASI)
            // WASI: performTurn may need multiple scheduling turns to unwind through
            // its own async call stack before reaching lease.end().
            // No fixed number of Task.yield() calls after breaking would be reliable.
            #else
            break
            #endif
        }
    }

    #if os(WASI)
    // In performTurn, lease.end() is called before turnRuntime.continuation.finish().
    // By the time the for loop exits (stream finished), the lease is guaranteed to be released.
    #else
    // Alternatively, performTurn should be executing concurrently on a different thread, and
    // by the time the test task reaches Task.yield(), the lease.end() should have already run.
    // The yield is a courtesy pause to give the scheduler a turn to run the cancelled task's cleanup.
    // NOTE: Does not seem to fail without it, I just got down this rabbit hole and felt proper.
    await Task.yield()
    #endif

    let secondText = try await completedAssistantText(from: try await session.send("second"))
    #expect(secondText == "Safe response")
}

@Test func explicitCancellation() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [.success("Response")])),
        behavior: .test(),
    )
    let session = agent.makeQueuedSession()

    let turn1 = await session.send("first")
    let turn2 = await session.send("second")
    await turn1.cancel()

    let events = try await collectedEvents(from: turn2)
    let receivedCompletion = events.contains { event in
        if case .result = event.kind {
            return true
        }
        return false
    }
    #expect(receivedCompletion)
}

@Test func consumerStreamEndsAfterCancel() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [.success("Response")])),
        behavior: .test(),
    )
    let session = agent.makeQueuedSession()

    let turn = await session.send("hello")
    await turn.cancel()

    var eventCount = 0
    for try await _ in turn.events {
        eventCount += 1
    }
    #expect(eventCount >= 0)
}

@Test func queueOrdering() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [
            .success("First response"),
            .success("Second response"),
        ])),
        behavior: .test(),
    )
    let session = agent.makeQueuedSession()

    let turn1 = await session.send("msg1")
    let turn2 = await session.send("msg2")

    let text1 = try await completedAssistantText(from: turn1)
    let text2 = try await completedAssistantText(from: turn2)

    #expect(text1 == "First response")
    #expect(text2 == "Second response")
}

@Test func selfDraining() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [
            .success("First"),
            .success("Second"),
        ])),
        behavior: .test(),
    )
    let session = agent.makeSession()

    let first = try await completedAssistantText(from: try await session.send("one"))
    let second = try await completedAssistantText(from: try await session.send("two"))

    #expect(first == "First")
    #expect(second == "Second")
}

@Test func independentAgents() async throws {
    let agent1 = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [.success("Response")])),
        behavior: .test(),
    )
    let agent2 = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [.success("Unused")])),
        behavior: .test(),
    )
    let session1 = agent1.makeSession()
    let session2 = agent2.makeSession()

    let response = try await completedAssistantText(from: try await session1.send("Hello"))
    #expect(response == "Response")

    let turn = try await session2.send("Hi")
    await turn.cancel()
    for try await _ in turn.events {}
}

@Test func agent_hasID() {
    let namedAgent = Agent(
        agentId: "myAgent",
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider()),
        behavior: .test(),
    )
    #expect(namedAgent.agentId == "myAgent")
}

@Test func agent_defaultIDIsUnique() {
    let agent1 = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider()),
        behavior: .test(),
    )
    let agent2 = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider()),
        behavior: .test(),
    )
    #expect(agent1.agentId != agent2.agentId)
}

@Test func agent_defaultOwnerIsLocal() {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider()),
        behavior: .test(),
    )
    #expect(agent.owner == .local)
}

@Test func agent_ownerMatchesInit() {
    let user: UserID = "alice"
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider()),
        behavior: .test(),
        owner: user,
    )
    #expect(agent.owner == user)
}

private func collectedEvents(from turn: Turn<AssistantMessage>) async throws -> [AgentEvent<AssistantMessage>] {
    var events: [AgentEvent<AssistantMessage>] = []
    for try await event in turn.events {
        events.append(event)
    }
    return events
}

private func completedAssistantText(from turn: Turn<AssistantMessage>) async throws -> String {
    let events = try await collectedEvents(from: turn)
    guard let message = events.compactMap({
        if case .result(let assistant) = $0.kind {
            return assistant.text
        }
        return nil
    }).last else {
        Issue.record("Expected a completed assistant message")
        return ""
    }
    return message
}
