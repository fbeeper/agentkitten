// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

@Suite("AgentTrace Retention Policy")
struct TraceRetentionPolicyTests {
    @Test func rollsOldTurns() async throws {
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                responses: [
                    .success("First"),
                    .success("Second"),
                ],
            )),
            behavior: .test(),
            traceRetentionPolicy: .maxTurns(1)
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("First")
        _ = try await collectEvents(from: firstTurn)
        let secondTurn = try await session.send("Second")
        _ = try await collectEvents(from: secondTurn)

        let trace = await session.trace
        let entries = await trace.snapshot()

        #expect(entries.allSatisfy { $0.invocationID == secondTurn.id })
        #expect(directTurnEntryKinds(in: entries) == [
            .turnStarted(UserMessage(text: "Second")),
            .message(.assistant(AssistantMessage(text: "Second"))),
            .turnCompleted(.completed),
        ])
    }

    @Test func keepsWholeDirectTurnWithToolMessages() async throws {
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                responses: [
                    .toolCall(
                        name: "counting_echo",
                        argumentsJSON: #"{"message":"first"}"#,
                        thenRespond: "First done."
                    ),
                    .toolCall(
                        name: "counting_echo",
                        argumentsJSON: #"{"message":"second"}"#,
                        thenRespond: "Second done."
                    ),
                ],
            )),
            behavior: .test(),
            toolDefinition: ToolDefinition(tools: [AnyAgentTool(CountingEchoTool(counter: ToolCallCounter()))]),
            traceRetentionPolicy: .maxTurns(1)
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("First request")
        _ = try await collectEvents(from: firstTurn)
        let secondTurn = try await session.send("Second request")
        _ = try await collectEvents(from: secondTurn)

        let entries = await directTurnEntries(for: secondTurn.id, on: session)

        #expect(entries.allSatisfy { $0.invocationID == secondTurn.id })
        // `directTurnEntries` intentionally excludes `executionPreparation` and
        // `conversationResolved`, so this count only covers the retained direct-turn entries below.
        #expect(entries.count == 5)
        #expect(entries[0].kind == AgentTraceEntry.Kind.turnStarted(UserMessage(text: "Second request")))
        guard case .message(.toolCall(let call)) = entries[1].kind else {
            Issue.record("Expected tool call entry")
            return
        }
        #expect(call.name == "counting_echo")
        #expect(call.argumentsJSON == #"{"message":"second"}"#)
        guard case .message(.toolResult(let result)) = entries[2].kind else {
            Issue.record("Expected tool result entry")
            return
        }
        #expect(result.callID == call.id)
        #expect(result.name == "counting_echo")
        #expect(result.contentSummary == [ToolResultContentSummary.text(#"{"echo":"second"}"#)])
        #expect(result.isError == false)
        #expect(
            entries[3].kind
                == AgentTraceEntry.Kind.message(.assistant(AssistantMessage(text: "Second done.")))
        )
        #expect(entries[4].kind == AgentTraceEntry.Kind.turnCompleted(.completed))
    }

    @Test func zeroOrNegativeLimitKeepsNoEntries() async throws {
        let zeroLimitSession = makeRetentionPolicySession(limit: 0)
        let zeroLimitTurn = try await zeroLimitSession.send("Hello")
        _ = try await collectEvents(from: zeroLimitTurn)
        let zeroLimitEntries = await zeroLimitSession.trace.snapshot()
        #expect(zeroLimitEntries.isEmpty)

        let negativeLimitSession = makeRetentionPolicySession(limit: -1)
        let negativeLimitTurn = try await negativeLimitSession.send("Hello again")
        _ = try await collectEvents(from: negativeLimitTurn)
        let negativeLimitEntries = await negativeLimitSession.trace.snapshot()
        #expect(negativeLimitEntries.isEmpty)
    }
}

private func makeRetentionPolicySession(limit: Int) -> AgentSession {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
            responses: [.success("Ignored")],
        )),
        behavior: .test(),
        traceRetentionPolicy: .maxTurns(limit)
    )
    return agent.makeSession()
}
