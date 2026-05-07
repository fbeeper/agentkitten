// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

private struct ApprovalStructuredValue: Codable, Sendable, JSONSchemaProviding, Equatable {
    let answer: String

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "answer": .string(description: "The answer"),
            ],
            required: ["answer"],
        )
    }
}

private struct ApprovalEventProvider: InferenceProviding {
    typealias Session = ApprovalEventSession

    let pendingToolCall: PendingToolCall
    let finalText: String

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) -> ApprovalEventSession {
        ApprovalEventSession(
            pendingToolCall: pendingToolCall,
            finalText: finalText
        )
    }
}

private actor ApprovalEventSession: InferenceSession, StructuredInferenceSession {
    private let pendingToolCall: PendingToolCall
    private let finalText: String

    init(
        pendingToolCall: PendingToolCall,
        finalText: String
    ) {
        self.pendingToolCall = pendingToolCall
        self.finalText = finalText
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .toolCallRequested(
                    id: pendingToolCall.id,
                    name: pendingToolCall.name,
                    argumentsJSON: pendingToolCall.argumentsJSON
                )
            )
            continuation.yield(.toolApprovalRequired(call: pendingToolCall))
            continuation.yield(.result(finalText, .endTurn))
            continuation.finish()
        }
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        throw .generationFailed(InferenceError.invalidResponse("structured generation not supported"))
    }
}

@Suite("Tool Approval Events")
struct ToolApprovalEventTests {
    @Test func digester_emitsApprovalRequiredAsNonTerminalChildOfToolStart() async throws {
        let pendingToolCall = PendingToolCall(
            id: "call-1",
            name: "echo",
            argumentsJSON: #"{"message":"approve"}"#,
        )

        let events = try await digestConversationEvents([
            .toolCallRequested(
                id: pendingToolCall.id,
                name: pendingToolCall.name,
                argumentsJSON: pendingToolCall.argumentsJSON
            ),
            .toolApprovalRequired(call: pendingToolCall),
            .result("Done.", .endTurn),
        ])

        #expect(events.count == 3)
        guard case .toolCallStarted(
            name: pendingToolCall.name,
            id: pendingToolCall.id,
            argumentsJSON: pendingToolCall.argumentsJSON
        ) = events[0].kind else {
            Issue.record("Expected toolCallStarted")
            return
        }
        guard case .toolApprovalRequired(let call) = events[1].kind else {
            Issue.record("Expected toolApprovalRequired")
            return
        }
        #expect(call == pendingToolCall)
        #expect(events[1].metadata.parentEventID == events[0].metadata.eventID)
        guard case .result(let message) = events[2].kind else {
            Issue.record("Expected terminal result")
            return
        }
        #expect(message == AssistantMessage(text: "Done."))
    }

    @Test func digester_keepsToolCompletionLinkedAfterApprovalRequired() async throws {
        let pendingToolCall = PendingToolCall(
            id: "call-1",
            name: "echo",
            argumentsJSON: #"{"message":"approve"}"#,
        )

        let events = try await digestConversationEvents([
            .toolCallRequested(
                id: pendingToolCall.id,
                name: pendingToolCall.name,
                argumentsJSON: pendingToolCall.argumentsJSON
            ),
            .toolApprovalRequired(call: pendingToolCall),
            .toolCallCompleted(
                id: pendingToolCall.id,
                name: pendingToolCall.name,
                outcome: .success(content: [.text(#"{"echo":"approve"}"#)])
            ),
            .result("Done.", .endTurn),
        ])

        #expect(events.count == 4)
        #expect(events[1].metadata.parentEventID == events[0].metadata.eventID)
        #expect(events[2].metadata.parentEventID == events[0].metadata.eventID)
    }

    @Test func conversationEventMapper_mapsApprovalRequiredAsSystemAuthoredChildOfToolStart() throws {
        let invocationID = InvocationID.generate()
        let conversationID = ConversationID.generate()
        let sessionID = AgentSessionID.generate()
        let pendingToolCall = PendingToolCall(
            id: "tool-1",
            name: "echo",
            argumentsJSON: #"{"message":"ok"}"#,
        )
        let startTimestamp = Date(timeIntervalSince1970: 1)
        let approvalTimestamp = Date(timeIntervalSince1970: 2)

        let started = ConversationEvent<AssistantMessage>(
            kind: .toolCallStarted(
                name: pendingToolCall.name,
                id: pendingToolCall.id,
                argumentsJSON: pendingToolCall.argumentsJSON,
            ),
            metadata: ConversationEvent<AssistantMessage>.Metadata(
                eventID: .generate(),
                conversationID: conversationID,
                timestamp: startTimestamp,
            )
        )
        let approvalRequired = ConversationEvent<AssistantMessage>(
            kind: .toolApprovalRequired(call: pendingToolCall),
            metadata: ConversationEvent<AssistantMessage>.Metadata(
                eventID: .generate(),
                conversationID: conversationID,
                timestamp: approvalTimestamp,
                parentEventID: started.metadata.eventID,
            )
        )

        var mapper = ConversationEventMapper<AssistantMessage>(
            agentID: "assistant",
            sessionID: sessionID,
            invocationID: invocationID
        )
        let startMapped = mapper.map(started)
        let approvalMapped = mapper.map(approvalRequired)
        let mappedStart = try #require(startMapped)
        let mappedApproval = try #require(approvalMapped)

        #expect(mappedApproval.kind == AgentEvent<AssistantMessage>.Kind.toolApprovalRequired(call: pendingToolCall))
        #expect(mappedApproval.metadata.sessionID == sessionID)
        #expect(mappedApproval.metadata.invocationID == invocationID)
        #expect(mappedApproval.metadata.timestamp == approvalTimestamp)
        #expect(mappedApproval.metadata.author == EventAuthor.system)
        #expect(mappedApproval.metadata.parentEventID == mappedStart.metadata.eventID)
    }

    @Test func structuredDigester_reachesStructuredResultAfterApprovalRequired() async throws {
        let pendingToolCall = PendingToolCall(
            id: "call-1",
            name: "echo",
            argumentsJSON: #"{"message":"approve"}"#,
        )
        let expected = ApprovalStructuredValue(answer: "structured")

        let events = try await digestStructuredConversationEvents([
            .toolCallRequested(
                id: pendingToolCall.id,
                name: pendingToolCall.name,
                argumentsJSON: pendingToolCall.argumentsJSON
            ),
            .toolApprovalRequired(call: pendingToolCall),
            .result(expected, .endTurn),
        ])

        #expect(events.count == 3)
        guard case .toolApprovalRequired(let call) = events[1].kind else {
            Issue.record("Expected toolApprovalRequired")
            return
        }
        #expect(call == pendingToolCall)
        guard case .result(let value) = events[2].kind else {
            Issue.record("Expected structured result")
            return
        }
        #expect(value == expected)
    }

    @Test func digester_throwsForApprovalRequiredWithoutPriorToolStart() async {
        let pendingToolCall = PendingToolCall(
            id: "call-1",
            name: "echo",
            argumentsJSON: #"{"message":"approve"}"#,
        )

        await #expect(throws: Error.self) {
            _ = try await digestConversationEvents([
                .toolApprovalRequired(call: pendingToolCall),
                .result("Done.", .endTurn),
            ])
        }
    }

    @Test func trace_recordsApprovalRequiredFromConversationStream() async throws {
        let pendingToolCall = PendingToolCall(
            id: "call-1",
            name: "echo",
            argumentsJSON: #"{"message":"approve"}"#,
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: ApprovalEventProvider(
                pendingToolCall: pendingToolCall,
                finalText: "Approved later"
            )),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Need approval")
        let events = try await collectEvents(from: turn)

        #expect(events.contains { event in
            event.kind == AgentEvent<AssistantMessage>.Kind.toolApprovalRequired(call: pendingToolCall)
        })
        #expect(directTurnEntryKinds(in: await directTurnEntries(for: turn.id, on: session)) == [
            .turnStarted(UserMessage(text: "Need approval")),
            .message(.toolCall(ToolCallMessage(
                id: pendingToolCall.id,
                name: pendingToolCall.name,
                argumentsJSON: pendingToolCall.argumentsJSON,
            ))),
            .toolApprovalRequired(.init(call: pendingToolCall)),
            .message(.assistant(AssistantMessage(text: "Approved later"))),
            .turnCompleted(.completed),
        ])
    }
}

private func digestConversationEvents(
    _ events: [InferenceEvent<String>]
) async throws -> [ConversationEvent<AssistantMessage>] {
    let stream = AsyncThrowingStream<InferenceEvent<String>, Error> { continuation in
        for event in events {
            continuation.yield(event)
        }
        continuation.finish()
    }
    let (output, continuation) = AsyncThrowingStream<ConversationEvent<AssistantMessage>, Error>.makeStream()
    let task = Task {
        let digester = InferenceDigester()
        do {
            try await digester.digest(
                stream: stream,
                continuation: continuation,
                conversationID: .generate()
            )
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
            throw error
        }
    }
    defer { task.cancel() }

    var collected: [ConversationEvent<AssistantMessage>] = []
    for try await event in output {
        collected.append(event)
    }
    try await task.value
    return collected
}

private func digestStructuredConversationEvents<T: Sendable>(
    _ events: [InferenceEvent<T>]
) async throws -> [ConversationEvent<T>] {
    let stream = AsyncThrowingStream<InferenceEvent<T>, Error> { continuation in
        for event in events {
            continuation.yield(event)
        }
        continuation.finish()
    }
    let (output, continuation) = AsyncThrowingStream<ConversationEvent<T>, Error>.makeStream()
    let task = Task {
        let digester = InferenceDigester()
        do {
            try await digester.digestStructured(
                stream: stream,
                continuation: continuation,
                conversationID: .generate()
            )
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
            throw error
        }
    }
    defer { task.cancel() }

    var collected: [ConversationEvent<T>] = []
    for try await event in output {
        collected.append(event)
    }
    try await task.value
    return collected
}
