// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

@Suite("AgentTrace Tool Messages")
struct TraceToolMessageTests {
    @Test func directExecution_recordsToolMessagesBeforeAssistant() async throws {
        let counter = ToolCallCounter()
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
                responses: [
                    .toolCall(
                        name: "counting_echo",
                        argumentsJSON: #"{"message":"hello"}"#,
                        thenRespond: "Done.",
                    ),
                ],
            )),
            behavior: .test(),
            toolDefinition: ToolDefinition(tools: [AnyAgentTool(CountingEchoTool(counter: counter))]),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Hello")
        _ = try await collectEvents(from: turn)

        let entries = await directTurnEntries(for: turn.id, on: session)
        #expect(entries.count == 5)
        #expect(entries[0].kind == AgentTraceEntry.Kind.turnStarted(UserMessage(text: "Hello")))

        guard case .message(.toolCall(let call)) = entries[1].kind else {
            Issue.record("Expected tool call trace entry")
            return
        }
        #expect(call.name == "counting_echo")
        #expect(call.argumentsJSON == #"{"message":"hello"}"#)

        guard case .message(.toolResult(let result)) = entries[2].kind else {
            Issue.record("Expected tool result trace entry")
            return
        }
        #expect(result.callID == call.id)
        #expect(result.name == "counting_echo")
        #expect(result.contentSummary == [ToolResultContentSummary.text(#"{"echo":"hello"}"#)])
        #expect(result.isError == false)

        #expect(entries[3].kind == AgentTraceEntry.Kind.message(.assistant(AssistantMessage(text: "Done."))))
        #expect(entries[4].kind == AgentTraceEntry.Kind.turnCompleted(.completed))
    }

    @Test func traceRetainsPerTurnToolMessagesAcrossMultipleTurns() async throws {
        let counter = ToolCallCounter()
        let agent = makeCountingEchoAgent(
            counter: counter,
            responses: [
                .toolCall(
                    name: "counting_echo",
                    argumentsJSON: #"{"message":"first"}"#,
                    thenRespond: "First done.",
                ),
                .toolCall(
                    name: "counting_echo",
                    argumentsJSON: #"{"message":"second"}"#,
                    thenRespond: "Second done.",
                ),
            ],
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("first")
        _ = try await collectEvents(from: firstTurn)
        let secondTurn = try await session.send("second")
        _ = try await collectEvents(from: secondTurn)

        let firstEntries = await directTurnEntries(for: firstTurn.id, on: session)
        let secondEntries = await directTurnEntries(for: secondTurn.id, on: session)

        #expect(firstEntries.count == 5)
        #expect(secondEntries.count == 5)

        assertToolMessages(
            entries: firstEntries,
            expectedArguments: #"{"message":"first"}"#,
            expectedAssistantText: "First done.",
        )
        assertToolMessages(
            entries: secondEntries,
            expectedArguments: #"{"message":"second"}"#,
            expectedAssistantText: "Second done.",
        )
    }
}

extension TraceToolMessageTests {
    private func makeCountingEchoAgent(
        counter: ToolCallCounter,
        responses: [MockResponse],
    ) -> Agent {
        Agent(
            providerRegistry: ProviderRegistry(
                default: ScriptedInferenceProvider(responses: responses),
            ),
            behavior: .test(),
            toolDefinition: ToolDefinition(
                tools: [AnyAgentTool(CountingEchoTool(counter: counter))],
            ),
        )
    }

    private func assertToolMessages(
        entries: [AgentTraceEntry],
        expectedArguments: String,
        expectedAssistantText: String,
    ) {
        guard case .message(.toolCall(let call)) = entries[1].kind else {
            Issue.record("Expected tool call entry")
            return
        }
        #expect(call.argumentsJSON == expectedArguments)

        guard case .message(.toolResult(let result)) = entries[2].kind else {
            Issue.record("Expected tool result entry")
            return
        }
        #expect(result.callID == call.id)
        #expect(
            entries[3].kind
                == AgentTraceEntry.Kind.message(
                    .assistant(AssistantMessage(text: expectedAssistantText)),
                ),
        )
    }
}
