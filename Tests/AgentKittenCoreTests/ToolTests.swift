// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

// MARK: - Test fixture: a concrete AgentTool

private struct EchoTool: AgentTool {
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

private struct RichEchoTool: RichAgentTool {
    struct Arguments: Codable, Sendable {
        let message: String
    }

    static let name = "rich_echo"
    static let description = "Returns text and image content."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["message": .string(description: "The message to echo.")],
            required: ["message"],
        ))
    }

    var capabilities: ToolCapabilities {
        ToolCapabilities(toolResultContentKinds: [.text, .image])
    }

    func execute(arguments: Arguments) async throws -> [ToolResultContent] {
        [
            .text(arguments.message),
            .image(mediaType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47])),
        ]
    }
}

// MARK: - AnyAgentTool wrapping

@Test func anyAgentToolWrapping() {
    let wrapped = AnyAgentTool(EchoTool())
    #expect(wrapped.name == "echo")
    #expect(wrapped.description == "Echoes the provided message back.")
}

@Test func anyAgentToolExecution() async throws {
    let wrapped = AnyAgentTool(EchoTool())
    let argsData = try JSONEncoder().encode(EchoTool.Arguments(message: "hello"))
    let resultContent = try await wrapped.execute(argumentsJSON: argsData)
    let text = try #require(singleTextContent(in: resultContent))
    let output = try JSONDecoder().decode(EchoTool.Output.self, from: Data(text.utf8))
    #expect(output.echo == "hello")
}

@Test func richAnyAgentToolExecution() async throws {
    let wrapped = AnyAgentTool(RichEchoTool())
    let argsData = try JSONEncoder().encode(RichEchoTool.Arguments(message: "hello"))
    let resultContent = try await wrapped.execute(argumentsJSON: argsData)
    #expect(resultContent == [
        .text("hello"),
        .image(mediaType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47])),
    ])
    #expect(wrapped.capabilities.toolResultContentKinds == [.text, .image])
}

// MARK: - Mock tool call simulation

@Test func conversationRunIncludesToolArgumentsInEvents() async throws {
    let conversation = Conversation(
        owner: .local,
        provider: MockInferenceProvider(mockResponses: [
            .toolCall(
                name: "echo",
                argumentsJSON: #"{"message":"hi"}"#,
                thenRespond: "The tool returned hi.",
            ),
        ]),
        systemPrompt: "Test",
        executionConfiguration: EffectiveExecutionConfiguration(
            inferenceConfiguration: InferenceConfiguration(),
        ),
        toolRuntime: testToolRuntime(
            registry: ToolRegistry([AnyAgentTool(EchoTool())]),
        ),
    )

    let stream = try await conversation.send(
        userMessage: UserMessage(text: "Call echo"),
        executionConfiguration: EffectiveExecutionConfiguration(),
        toolExecutionContext: .empty,
    )
    for try await event in stream {
        guard case .toolCallStarted(let name, _, let argumentsJSON) = event.kind else {
            continue
        }
        #expect(name == "echo")
        #expect(argumentsJSON == #"{"message":"hi"}"#)
        return
    }

    Issue.record("Expected a toolCallStarted conversation event")
}

@Test func conversationRunEmitsConversationEvents() async throws {
    let conversation = Conversation(
        owner: .local,
        provider: MockInferenceProvider(mockResponses: [
            .toolCall(
                name: "echo",
                argumentsJSON: #"{"message":"test"}"#,
                thenRespond: "Done.",
            ),
        ]),
        systemPrompt: "Test",
        executionConfiguration: EffectiveExecutionConfiguration(
            inferenceConfiguration: InferenceConfiguration(),
        ),
        toolRuntime: testToolRuntime(
            registry: ToolRegistry([AnyAgentTool(EchoTool())]),
        ),
    )

    var events: [ConversationEvent<AssistantMessage>] = []
    for try await event in try await conversation.send(
        userMessage: UserMessage(text: "Call echo"),
        executionConfiguration: EffectiveExecutionConfiguration(),
        toolExecutionContext: .empty,
    ) {
        events.append(event)
    }

    #expect(!events.isEmpty)
    let conversationID = try #require(events.first?.metadata.conversationID)
    #expect(events.allSatisfy { $0.metadata.conversationID == conversationID })

    let started = try #require(firstToolCallStarted(in: events))
    let completed = try #require(firstToolCallCompleted(in: events))
    #expect(completed.metadata.parentEventID == started.metadata.eventID)

    let assistant = try #require(lastAssistantMessage(in: events))
    #expect(assistant.text == "Done.")

    guard case .toolCallStarted(let name, _, let argumentsJSON) = started.kind else {
        Issue.record("Expected toolCallStarted payload")
        return
    }
    #expect(name == "echo")
    #expect(argumentsJSON == #"{"message":"test"}"#)
}

@Test func toolCallAgentEvents() async throws {
    let provider = ScriptedInferenceProvider(responses: [
        .toolCall(
            name: "echo",
            argumentsJSON: #"{"message":"test"}"#,
            thenRespond: "Done.",
        ),
    ])
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: provider),
        behavior: .test(),
        toolDefinition: ToolDefinition(tools: [AnyAgentTool(EchoTool())]),
    )
    let session = agent.makeSession()

    var events: [AgentEvent<AssistantMessage>] = []
    for try await event in try await session.send("go").events {
        events.append(event)
    }

    let hasStarted = events.contains {
        if case .toolCallStarted(let name, _) = $0.kind { return name == "echo" }
        return false
    }
    #expect(hasStarted, "Expected toolCallStarted event for echo")

    let hasCompleted = events.contains {
        if case .toolCallCompleted(let name, _, let outcome) = $0.kind,
           name == "echo", case .success = outcome { return true }
        return false
    }
    #expect(hasCompleted, "Expected successful toolCallCompleted event for echo")

    guard let last = events.last, case .result(let assistantMsg) = last.kind else {
        Issue.record("Last event should be result with assistant message"); return
    }
    #expect(assistantMsg.text == "Done.")
}

@Test func resultCarriesAssistantMessage() async throws {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [.success("Hello world")])),
        behavior: .test(),
    )
    let session = agent.makeSession()

    var completedMessage: AssistantMessage?
    for try await event in try await session.send("Hi").events {
        if case .result(let msg) = event.kind {
            completedMessage = msg
        }
    }

    guard let msg = completedMessage else {
        Issue.record("result should carry an assistant message"); return
    }
    #expect(msg.text == "Hello world")
}

private func firstToolCallStarted(
    in events: [ConversationEvent<AssistantMessage>],
) -> ConversationEvent<AssistantMessage>? {
    events.first {
        if case .toolCallStarted = $0.kind {
            return true
        }
        return false
    }
}

private func firstToolCallCompleted(
    in events: [ConversationEvent<AssistantMessage>],
) -> ConversationEvent<AssistantMessage>? {
    events.first {
        if case .toolCallCompleted = $0.kind {
            return true
        }
        return false
    }
}

private func lastAssistantMessage(
    in events: [ConversationEvent<AssistantMessage>],
) -> AssistantMessage? {
    guard let last = events.last,
          case .result(let assistant) = last.kind else {
        return nil
    }
    return assistant
}
