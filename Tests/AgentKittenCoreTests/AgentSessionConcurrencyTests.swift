// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

private struct BusyStructuredLabel: Codable, Sendable, JSONSchemaProviding, Equatable {
    let value: String

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "value": .string(description: "Busy-test value"),
            ],
            required: ["value"]
        )
    }
}

private final class TurnDropWitness<Result: Sendable> {
    weak var turn: Turn<Result>?
}

private enum TurnDropTestError: Error {
    case sessionDidNotBecomeIdle(String)
}

private func startAndDropAssistantTurn(
    _ text: String,
    in session: AgentSession,
    provider: GateInferenceProvider
) async throws -> TurnDropWitness<AssistantMessage> {
    let witness = TurnDropWitness<AssistantMessage>()

    do {
        let turn = try await session.send(text)
        witness.turn = turn
        await provider.waitUntilStarted(text)
    }

    return witness
}

private func startAndDropStructuredTurn(
    _ prompt: String,
    in session: AgentSession,
    provider: GateStructuredDropProvider
) async throws -> TurnDropWitness<BusyStructuredLabel> {
    let witness = TurnDropWitness<BusyStructuredLabel>()

    do {
        let turn: Turn<BusyStructuredLabel> = try await session.generate(prompt)
        witness.turn = turn
        await provider.waitUntilStarted(prompt)
    }

    return witness
}

private func sendWhenIdle(
    _ text: String,
    in session: AgentSession
) async throws -> Turn<AssistantMessage> {
    for _ in 0..<100 {
        do {
            return try await session.send(text)
        } catch AgentSessionError.concurrentOperationInProgress {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    Issue.record("Expected session to become idle before sending '\(text)'")
    throw TurnDropTestError.sessionDidNotBecomeIdle(text)
}

private func generateWhenIdle<Result: Codable & Sendable & JSONSchemaProviding>(
    _ prompt: String,
    in session: AgentSession
) async throws -> Turn<Result> {
    for _ in 0..<100 {
        do {
            return try await session.generate(prompt)
        } catch AgentSessionError.concurrentOperationInProgress {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    Issue.record("Expected session to become idle before generating '\(prompt)'")
    throw TurnDropTestError.sessionDidNotBecomeIdle(prompt)
}

@Suite("AgentSession Concurrency")
struct AgentSessionConcurrencyTests {
    @Test func directSessionRejectsConcurrentSend() async throws {
        let provider = GateInferenceProvider()
        let agent = Agent(
            provider: provider,
            behavior: .test(),
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("a1")
        let firstTask = Task { try await collectEvents(from: firstTurn) }
        await provider.waitUntilStarted("a1")

        await #expect(throws: AgentSessionError.concurrentOperationInProgress(active: .run)) {
            _ = try await session.send("a2")
        }

        await provider.release("a1")
        _ = try await firstTask.value
    }

    @Test func directSessionCancellationReleasesBusyGuard() async throws {
        let provider = GateInferenceProvider()
        let agent = Agent(
            provider: provider,
            behavior: .test(),
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("a1")
        let firstTask = Task { try await collectEvents(from: firstTurn) }
        await provider.waitUntilStarted("a1")

        await firstTurn.cancel()
        await provider.release("a1")
        _ = try await firstTask.value

        let secondTurn = try await session.send("a2")
        let secondTask = Task { try await collectEvents(from: secondTurn) }
        await provider.waitUntilStarted("a2")
        await provider.release("a2")
        _ = try await secondTask.value
    }

    /// Dropping a `Turn` without consuming its events should cancel the underlying
    /// generation task without requiring an explicit `turn.cancel()` call.
    @Test func droppingTurnWithoutConsumingCancelsGeneration() async throws {
        let provider = GateInferenceProvider()
        let agent = Agent(
            provider: provider,
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turnWitness = try await startAndDropAssistantTurn(
            "drop-me",
            in: session,
            provider: provider
        )

        for _ in 0..<20 where turnWitness.turn != nil {
            await Task.yield()
        }

        #expect(turnWitness.turn == nil)

        // The gate provider is parked until released; opening the gate lets the
        // provider task reach its cancellation check and record the signal below.
        await provider.release("drop-me")
        #expect(await eventually {
            await provider.wasCancelled("drop-me")
        })

        let secondTurn = try await sendWhenIdle("after-drop", in: session)
        await provider.release("after-drop")
        _ = try await collectEvents(from: secondTurn)
    }

    @Test func droppingStructuredTurnWithoutConsumingCancelsGeneration() async throws {
        let provider = GateStructuredDropProvider(
            structuredJSON: #"{"value":"done"}"#
        )
        let agent = Agent(
            provider: provider,
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turnWitness = try await startAndDropStructuredTurn(
            "drop-structured",
            in: session,
            provider: provider
        )

        for _ in 0..<20 where turnWitness.turn != nil {
            await Task.yield()
        }

        #expect(turnWitness.turn == nil)

        // The gate provider is parked until released; opening the gate lets the
        // provider task reach its cancellation check and record the signal below.
        await provider.release("drop-structured")
        #expect(await eventually {
            await provider.wasCancelled("drop-structured")
        })

        let secondTurn: Turn<BusyStructuredLabel> = try await generateWhenIdle(
            "after-structured-drop",
            in: session
        )
        await provider.release("after-structured-drop")
        _ = try await firstStructuredResult(from: secondTurn)
    }

    @Test func directSessionRejectsGenerateDuringActiveSend() async throws {
        let provider = GateInferenceProvider()
        let agent = Agent(
            provider: provider,
            behavior: .test(),
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("a1")
        let firstTask = Task { try await collectEvents(from: firstTurn) }
        await provider.waitUntilStarted("a1")

        await #expect(throws: AgentSessionError.concurrentOperationInProgress(active: .run)) {
            let _: Turn<BusyStructuredLabel> = try await session.generate("structured")
        }

        await provider.release("a1")
        _ = try await firstTask.value
    }
}

private struct GateStructuredDropProvider: InferenceProviding {
    typealias Session = GateStructuredDropSession

    let state = GateInferenceState()
    let structuredJSON: String

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) -> GateStructuredDropSession {
        GateStructuredDropSession(
            state: state,
            structuredJSON: structuredJSON
        )
    }

    func waitUntilStarted(_ text: String) async {
        await state.waitUntilStarted(text)
    }

    func wasCancelled(_ text: String) async -> Bool {
        await state.wasCancelled(text)
    }

    func release(_ text: String) async {
        await state.release(text)
    }
}

private actor GateStructuredDropSession: InferenceSession, StructuredInferenceSession {
    private let state: GateInferenceState
    private let structuredJSON: String

    init(
        state: GateInferenceState,
        structuredJSON: String
    ) {
        self.state = state
        self.structuredJSON = structuredJSON
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        throw InferenceError.invalidResponse("unstructured generation not supported")
    }

    func generateStream<Result: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters
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
                    await state.markCancelled(prompt)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: StructuredGenerationError.decodingFailed(error))
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    Task { await self.state.markCancelled(prompt) }
                }
                task.cancel()
            }
        }
    }
}

private func firstStructuredResult<Result>(
    from turn: Turn<Result>
) async throws -> Result {
    var result: Result?
    for try await event in turn.events {
        if case .result(let value) = event.kind {
            result = value
        }
    }
    return try #require(result, "Expected a structured result")
}
