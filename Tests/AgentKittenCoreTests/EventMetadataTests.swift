// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

private struct EventMetadataEchoTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let message: String
    }

    struct Output: Codable, Sendable {
        let echo: String
    }

    static let name = "echo"
    static let description = "Echoes the provided message back."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["message": .string(description: "The message to echo.")],
            required: ["message"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(echo: arguments.message)
    }
}

struct EventMetadataValueTests {
    @Test func construction_fieldsReadable() {
        let metadata = AgentEvent<AssistantMessage>.Metadata(
            eventID: .generate(),
            sessionID: .generate(),
            invocationID: .generate(),
            author: .system,
            timestamp: Date(timeIntervalSince1970: 123),
            parentEventID: .generate(),
        )

        #expect(metadata.author == .system)
        #expect(metadata.timestamp == Date(timeIntervalSince1970: 123))
        #expect(metadata.eventID != metadata.parentEventID)
        #expect(metadata.parentEventID != nil)
    }

    @Test func eventMetadata_codableRoundTrip() throws {
        let original = AgentEvent<AssistantMessage>.Metadata(
            eventID: .generate(),
            sessionID: .generate(),
            invocationID: .generate(),
            author: .agent("planner"),
            timestamp: Date(timeIntervalSince1970: 456),
            parentEventID: .generate(),
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentEvent<AssistantMessage>.Metadata.self, from: data)
        #expect(decoded == original)
    }

    @Test(arguments: [
        EventAuthor.user("alice"),
        EventAuthor.agent("assistant"),
        EventAuthor.tool("echo"),
        EventAuthor.system,
    ])
    func eventAuthor_codableRoundTrip(_ author: EventAuthor) throws {
        let data = try JSONEncoder().encode(author)
        let decoded = try JSONDecoder().decode(EventAuthor.self, from: data)
        #expect(decoded == author)
    }
}

struct AgentEventMetadataMapperTests {
    // swiftlint:disable:next function_body_length
    @Test func conversationEventMapper_createsFreshAgentIDsAndPreservesToolLinkage() throws {
        let invocationID = InvocationID.generate()
        let conversationID = ConversationID.generate()
        let sessionID = AgentSessionID.generate()
        let toolID = "tool-1"
        let startTimestamp = Date(timeIntervalSince1970: 1)
        let completionTimestamp = Date(timeIntervalSince1970: 2)

        let conversationStarted = ConversationEvent<AssistantMessage>(
            kind: .toolCallStarted(
                name: "echo",
                id: toolID,
                argumentsJSON: #"{"message":"ok"}"#,
            ),
            metadata: ConversationEvent<AssistantMessage>.Metadata(
                eventID: .generate(),
                conversationID: conversationID,
                timestamp: startTimestamp,
            ),
        )
        let conversationCompleted = ConversationEvent<AssistantMessage>(
            kind: .toolCallCompleted(
                name: "echo",
                id: toolID,
                outcome: .success(content: [.text(#"{"echo":"ok"}"#)]),
            ),
            metadata: ConversationEvent<AssistantMessage>.Metadata(
                eventID: .generate(),
                conversationID: conversationID,
                timestamp: completionTimestamp,
                parentEventID: conversationStarted.metadata.eventID,
            ),
        )

        var mapper = ConversationEventMapper<AssistantMessage>(
            agentID: "assistant",
            sessionID: sessionID,
            invocationID: invocationID,
        )
        let startedMapped = mapper.map(conversationStarted)
        let completedMapped = mapper.map(conversationCompleted)
        let started = try #require(startedMapped)
        let completed = try #require(completedMapped)

        #expect(started.metadata.eventID != conversationStarted.metadata.eventID)
        #expect(completed.metadata.eventID != conversationCompleted.metadata.eventID)
        #expect(started.metadata.sessionID == sessionID)
        #expect(completed.metadata.sessionID == sessionID)
        #expect(started.metadata.invocationID == invocationID)
        #expect(completed.metadata.invocationID == invocationID)
        #expect(started.metadata.timestamp == startTimestamp)
        #expect(completed.metadata.timestamp == completionTimestamp)
        #expect(started.metadata.author == .agent("assistant"))
        #expect(completed.metadata.author == EventAuthor.tool("echo"))
        #expect(completed.metadata.parentEventID == started.metadata.eventID)
    }

    @Test func conversationEventMapper_mapsStructuredToolEvents() throws {
        let invocationID = InvocationID.generate()
        let conversationID = ConversationID.generate()
        let sessionID = AgentSessionID.generate()
        let toolID = "tool-1"
        let startTimestamp = Date(timeIntervalSince1970: 1)
        let completionTimestamp = Date(timeIntervalSince1970: 2)

        let (conversationStarted, conversationCompleted) = Self.makeStructuredToolConversationEvents(
            conversationID: conversationID,
            toolID: toolID,
            startTimestamp: startTimestamp,
            completionTimestamp: completionTimestamp,
        )

        var mapper = ConversationEventMapper<String>(
            agentID: "assistant",
            sessionID: sessionID,
            invocationID: invocationID,
        )
        let startedMapped = mapper.map(conversationStarted)
        let completedMapped = mapper.map(conversationCompleted)
        let started = try #require(startedMapped)
        let completed = try #require(completedMapped)

        #expect(started.kind == AgentEvent<String>.Kind.toolCallStarted(name: "echo", id: toolID))
        #expect(completed.kind == AgentEvent<String>.Kind.toolCallCompleted(
            name: "echo",
            id: toolID,
            outcome: .success(content: [.text(#"{"echo":"ok"}"#)]),
        ))
        Self.expectToolEventMetadata(
            started: started,
            completed: completed,
            expected: .init(
                sessionID: sessionID,
                invocationID: invocationID,
                startTimestamp: startTimestamp,
                completionTimestamp: completionTimestamp,
            ),
        )
    }

    private struct ToolEventMetadataExpectation {
        let sessionID: AgentSessionID
        let invocationID: InvocationID
        let startTimestamp: Date
        let completionTimestamp: Date
    }

    private static func makeStructuredToolConversationEvents(
        conversationID: ConversationID,
        toolID: String,
        startTimestamp: Date,
        completionTimestamp: Date,
    ) -> (ConversationEvent<String>, ConversationEvent<String>) {
        let started = ConversationEvent<String>(
            kind: .toolCallStarted(
                name: "echo",
                id: toolID,
                argumentsJSON: #"{"message":"ok"}"#,
            ),
            metadata: ConversationEvent<String>.Metadata(
                eventID: .generate(),
                conversationID: conversationID,
                timestamp: startTimestamp,
            ),
        )
        let completed = ConversationEvent<String>(
            kind: .toolCallCompleted(
                name: "echo",
                id: toolID,
                outcome: .success(content: [.text(#"{"echo":"ok"}"#)]),
            ),
            metadata: ConversationEvent<String>.Metadata(
                eventID: .generate(),
                conversationID: conversationID,
                timestamp: completionTimestamp,
                parentEventID: started.metadata.eventID,
            ),
        )
        return (started, completed)
    }

    private static func expectToolEventMetadata<Result: Sendable>(
        started: AgentEvent<Result>,
        completed: AgentEvent<Result>,
        expected: ToolEventMetadataExpectation,
    ) {
        #expect(started.metadata.sessionID == expected.sessionID)
        #expect(completed.metadata.sessionID == expected.sessionID)
        #expect(started.metadata.invocationID == expected.invocationID)
        #expect(completed.metadata.invocationID == expected.invocationID)
        #expect(started.metadata.timestamp == expected.startTimestamp)
        #expect(completed.metadata.timestamp == expected.completionTimestamp)
        #expect(started.metadata.author == .agent("assistant"))
        #expect(completed.metadata.author == EventAuthor.tool("echo"))
        #expect(completed.metadata.parentEventID == started.metadata.eventID)
    }
}

struct AgentTurnEventMetadataTests {
    @Test func invocationIDConsistencyWithinTurn_andTurnIDStability() async throws {
        let agent = Agent(
            agentId: "assistant",
            providerRegistry: ProviderRegistry(
                default: ScriptedInferenceProvider(responses: [.success("Hello world")]),
            ),
            behavior: .test(),
        )
        let session = agent.makeSession()
        let turn = try await session.send("Hi")

        let firstID = turn.id
        let secondID = turn.id
        #expect(firstID == secondID)

        var events: [AgentEvent<AssistantMessage>] = []
        for try await event in turn.events {
            events.append(event)
        }

        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.metadata.sessionID == session.sessionID })
        #expect(events.allSatisfy { $0.metadata.invocationID == firstID })
        #expect(events.allSatisfy { $0.metadata.author == .agent("assistant") })
    }

    @Test func separateTurnsHaveDifferentInvocationIDs() async throws {
        let agent = Agent(
            agentId: "assistant",
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [
                .success("First"),
                .success("Second"),
            ])),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn1 = try await session.send("one")
        let turn1ID = turn1.id
        var turn1Events: [AgentEvent<AssistantMessage>] = []
        for try await event in turn1.events {
            turn1Events.append(event)
        }

        let turn2 = try await session.send("two")
        let turn2ID = turn2.id
        var turn2Events: [AgentEvent<AssistantMessage>] = []
        for try await event in turn2.events {
            turn2Events.append(event)
        }

        #expect(turn1ID != turn2ID)
        #expect(turn1Events.allSatisfy { $0.metadata.sessionID == session.sessionID })
        #expect(turn1Events.allSatisfy { $0.metadata.invocationID == turn1ID })
        #expect(turn2Events.allSatisfy { $0.metadata.sessionID == session.sessionID })
        #expect(turn2Events.allSatisfy { $0.metadata.invocationID == turn2ID })
    }

    @Test func toolCompletionLinksToStartedEvent_andTimestampsAreOrdered() async throws {
        let provider = ScriptedInferenceProvider(responses: [
            .toolCall(
                name: "echo",
                argumentsJSON: #"{"message":"test"}"#,
                thenRespond: "Done.",
            ),
        ])
        let agent = Agent(
            agentId: "assistant",
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
            toolDefinition: ToolDefinition(tools: [AnyAgentTool(EventMetadataEchoTool())]),
        )
        let session = agent.makeSession()
        let turn = try await session.send("go")
        let turnID = turn.id

        var events: [AgentEvent<AssistantMessage>] = []
        for try await event in turn.events {
            events.append(event)
        }

        let started = try #require(events.first {
            if case .toolCallStarted = $0.kind {
                return true
            }
            return false
        })
        let completed = try #require(events.first {
            if case .toolCallCompleted = $0.kind {
                return true
            }
            return false
        })

        #expect(completed.metadata.parentEventID == started.metadata.eventID)
        #expect(events.allSatisfy { $0.metadata.sessionID == session.sessionID })
        #expect(events.allSatisfy { $0.metadata.invocationID == turnID })
        #expect(started.metadata.author == .agent("assistant"))
        #expect(completed.metadata.author == .tool("echo"))

        for index in 1 ..< events.count {
            #expect(events[index - 1].metadata.timestamp <= events[index].metadata.timestamp)
        }
    }

    @Test func toolStepLimitFailureIsSystemAuthored() async throws {
        let provider = ScriptedInferenceProvider(responses: [
            .toolCall(
                name: "echo",
                argumentsJSON: #"{"message":"blocked"}"#,
                thenRespond: "Done.",
            ),
        ])
        let agent = Agent(
            agentId: "assistant",
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
            toolDefinition: ToolDefinition(tools: [AnyAgentTool(EventMetadataEchoTool())]),
            toolBehavior: ToolBehavior(defaultStepBudget: .disabled),
        )
        let session = agent.makeSession()
        let turn = try await session.send("go")

        var events: [AgentEvent<AssistantMessage>] = []
        for try await event in turn.events {
            events.append(event)
        }

        let started = try #require(events.first {
            if case .toolCallStarted = $0.kind {
                return true
            }
            return false
        })
        let completed = try #require(events.first {
            if case .toolCallCompleted = $0.kind {
                return true
            }
            return false
        })

        #expect(started.metadata.author == .agent("assistant"))
        #expect(completed.metadata.author == .system)
        #expect(completed.metadata.parentEventID == started.metadata.eventID)
        if case .toolCallCompleted(_, _, let outcome) = completed.kind {
            #expect(outcome == .failure(.stepLimitExceeded))
        } else {
            Issue.record("Expected toolCallCompleted event")
        }
    }
}
