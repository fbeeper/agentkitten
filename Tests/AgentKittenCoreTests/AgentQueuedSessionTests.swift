// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

private struct QueuedStructuredLabel: Codable, Sendable, JSONSchemaProviding, Equatable {
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

@Suite("AgentQueuedSession")
struct AgentQueuedSessionTests {
    @Test func clearContext_runsInQueueBeforeLaterTurnStarts() async throws {
        let provider = GateInferenceProvider()
        let agent = Agent(
            provider: provider,
            behavior: .test(),
        )
        let session = agent.makeQueuedSession()

        let firstTurn = await session.send("First")
        let firstTask = Task { try await collectEvents(from: firstTurn) }
        await provider.waitUntilStarted("First")

        let clearTask = Task {
            try await session.clearContext(state: .preserve)
        }
        await Task.yield()
        let secondTurn = await session.send("Second")

        let traceBeforeRelease = await session.trace.snapshot()
        #expect(!traceBeforeRelease.contains { $0.invocationID == secondTurn.id })

        await provider.release("First")
        _ = try await firstTask.value
        try await clearTask.value

        await provider.waitUntilStarted("Second")
        await provider.release("Second")
        _ = try await collectEvents(from: secondTurn)

        let firstConversationID = try #require(
            await conversationID(for: firstTurn.id, on: session.trace),
        )
        let secondConversationID = try #require(
            await conversationID(for: secondTurn.id, on: session.trace),
        )

        #expect(firstConversationID != secondConversationID)
    }

    @Test func contextUsageAndCompaction_runInQueuedOrder() async throws {
        let agent = Agent(
            provider: MockInferenceProvider(
                responses: ["one two three four five"],
            ),
            behavior: .test(),
        )
        let session = agent.makeQueuedSession()

        let turn = await session.send("12345678901234567890")
        let maintenanceTask = Task {
            let usageBefore = try await session.contextUsage()
            let compaction = try await session.compactContext(
                .truncate(ContextCompactionOptions.TruncationOptions(preservedRecentTurnCount: 0)),
            )
            let usageAfter = try await session.contextUsage()
            return (usageBefore, compaction, usageAfter)
        }

        _ = try await collectEvents(from: turn)
        let (usageBefore, compaction, usageAfter) = try await maintenanceTask.value

        let compacted = try #require(compactedResult(from: compaction))
        #expect(usageBefore == ContextUsage(contextTokens: 5, contextSize: 100))
        #expect(compacted.usageBefore == usageBefore)
        #expect(compacted.usageAfter == ContextUsage(contextTokens: 0, contextSize: 100))
        #expect(usageAfter == compacted.usageAfter)
    }

    @Test func structuredGeneration_waitsForQueuedMaintenanceOperation() async throws {
        let provider = GateStructuredInferenceProvider(
            structuredJSON: #"{"name":"queued","score":0.7}"#,
        )
        let agent = Agent(
            provider: provider,
            behavior: .test(),
        )
        let session = agent.makeQueuedSession()

        let firstTurn = await session.send("First")
        let firstTask = Task { try await collectEvents(from: firstTurn) }
        await provider.waitUntilStarted("First")

        let clearTask = Task {
            try await session.clearContext(state: .preserve)
        }
        await Task.yield()
        let structuredTurn: Turn<QueuedStructuredLabel> = await session.generate("structured")

        await provider.release("First")
        _ = try await firstTask.value
        try await clearTask.value

        await provider.waitUntilStarted("structured")
        await provider.release("structured")
        let structuredResult = try await firstStructuredResult(from: structuredTurn)

        let firstConversationID = try #require(
            await conversationID(for: firstTurn.id, on: session.trace),
        )
        let structuredConversationID = try #require(
            await conversationID(for: structuredTurn.id, on: session.trace),
        )

        #expect(structuredResult == QueuedStructuredLabel(name: "queued", score: 0.7))
        #expect(firstConversationID != structuredConversationID)
    }

    @Test func cancelledQueuedTurn_neverStartsAndDoesNotBlockLaterTurns() async throws {
        let provider = GateInferenceProvider()
        let agent = Agent(
            provider: provider,
            behavior: .test(),
        )
        let session = agent.makeQueuedSession()

        let firstTurn = await session.send("First")
        let firstTask = Task { try await collectEvents(from: firstTurn) }
        await provider.waitUntilStarted("First")

        let cancelledTurn = await session.send("Cancelled")
        let thirdTurn = await session.send("Third")

        await cancelledTurn.cancel()
        let cancelledEvents = try await collectEvents(from: cancelledTurn)

        await provider.release("First")
        _ = try await firstTask.value

        #expect(await eventually {
            await provider.hasStarted("Third")
        })
        #expect(!(await provider.hasStarted("Cancelled")))

        await provider.release("Third")
        let thirdEvents = try await collectEvents(from: thirdTurn)

        #expect(cancelledEvents.isEmpty)
        #expect(assistantCompletions(in: thirdEvents) == ["waiting Third done"])
        #expect(await rawTraceEntries(for: cancelledTurn.id, on: session.trace).isEmpty)
    }

    @Test func droppedQueuedTurn_neverStartsAndDoesNotBlockLaterTurns() async throws {
        let provider = GateInferenceProvider()
        let agent = Agent(
            provider: provider,
            behavior: .test(),
        )
        let session = agent.makeQueuedSession()

        let firstTurn = await session.send("First")
        let firstTask = Task { try await collectEvents(from: firstTurn) }
        await provider.waitUntilStarted("First")

        weak var droppedTurn: Turn<AssistantMessage>?
        let droppedTurnID: InvocationID
        do {
            let turn = await session.send("Dropped")
            droppedTurn = turn
            droppedTurnID = turn.id
        }

        for _ in 0 ..< 20 where droppedTurn != nil {
            await Task.yield()
        }
        #expect(droppedTurn == nil)

        let thirdTurn = await session.send("Third")

        await provider.release("First")
        _ = try await firstTask.value

        #expect(await eventually {
            await provider.hasStarted("Third")
        })
        #expect(!(await provider.hasStarted("Dropped")))

        await provider.release("Third")
        let thirdEvents = try await collectEvents(from: thirdTurn)

        #expect(assistantCompletions(in: thirdEvents) == ["waiting Third done"])
        #expect(await rawTraceEntries(for: droppedTurnID, on: session.trace).isEmpty)
    }
}

private struct GateStructuredInferenceProvider: InferenceProviding {
    typealias Session = GateStructuredInferenceSession

    let state = GateInferenceState()
    let structuredJSON: String

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> GateStructuredInferenceSession {
        GateStructuredInferenceSession(
            state: state,
            structuredJSON: structuredJSON,
        )
    }

    func waitUntilStarted(_ text: String) async {
        await state.waitUntilStarted(text)
    }

    func hasStarted(_ text: String) async -> Bool {
        await state.hasStarted(text)
    }

    func release(_ text: String) async {
        await state.release(text)
    }
}

private actor GateStructuredInferenceSession: InferenceSession, StructuredInferenceSession {
    private let state: GateInferenceState
    private let structuredJSON: String

    init(
        state: GateInferenceState,
        structuredJSON: String,
    ) {
        self.state = state
        self.structuredJSON = structuredJSON
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        let task = Task {
            await state.markStarted(message.text)
            continuation.yield(.delta("waiting \(message.text)"))
            await state.waitUntilReleased(message.text)
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }
            continuation.yield(.result("waiting \(message.text) done", .endTurn))
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }

    func generateStream<Result: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<Result> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    await state.markStarted(prompt)
                    await state.waitUntilReleased(prompt)
                    try Task.checkCancellation()
                    let result = try JSONDecoder().decode(Result.self, from: Data(structuredJSON.utf8))
                    continuation.yield(.result(result, .endTurn))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: StructuredGenerationError.decodingFailed(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private func conversationID(
    for invocationID: InvocationID,
    on trace: AgentTrace,
) async -> String? {
    for entry in await rawTraceEntries(for: invocationID, on: trace) {
        if case .conversationResolved(let info) = entry.kind {
            return info.identity.conversationID
        }
    }
    return nil
}

private func firstStructuredResult<Result>(
    from turn: Turn<Result>,
) async throws -> Result {
    var result: Result?
    for try await event in turn.events {
        if case .result(let value) = event.kind {
            result = value
        }
    }
    return try #require(result, "Expected a structured result")
}

func eventually(
    maxAttempts: Int = 100,
    operation: @escaping @Sendable () async -> Bool,
) async -> Bool {
    for _ in 0 ..< maxAttempts {
        if await operation() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await operation()
}

private func compactedResult(
    from result: ContextCompactionResult,
) -> ContextCompactionResult.Compacted? {
    guard case .compacted(let compacted) = result else {
        return nil
    }
    return compacted
}
