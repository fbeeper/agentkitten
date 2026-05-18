// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

struct ScriptedInferenceProvider: InferenceProviding {
    typealias Session = ScriptedInferenceSession

    let script: SharedScript

    init(
        responses: [MockResponse] = [.success("This is a mock response.")],
        structuredResponses: [MockResponse] = [],
    ) {
        script = SharedScript(
            responses: responses,
            structuredResponses: structuredResponses,
        )
    }

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext = .empty,
    ) -> ScriptedInferenceSession {
        ScriptedInferenceSession(
            script: script,
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
        )
    }
}

actor ToolCallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

struct CountingEchoTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let message: String
    }

    struct Output: Codable, Sendable {
        let echo: String
    }

    static let name = "counting_echo"
    static let description = "Echoes the provided message and records execution count."

    let counter: ToolCallCounter

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "message": .string(description: "The message to echo."),
            ],
            required: ["message"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        await counter.increment()
        return Output(echo: arguments.message)
    }
}

func testToolRuntime(
    registry: ToolRegistry = ToolRegistry(),
    executionPolicy: some ToolExecutionPolicy = AutoApprovePolicy(),
) -> ToolRuntime {
    ToolRuntime(
        configuration: ToolDefinition(
            tools: registry.all,
            executionPolicy: executionPolicy,
        ),
    )
}

func singleTextContent(in content: [ToolResultContent]) -> String? {
    guard content.count == 1, case .text(let text) = content[0] else {
        return nil
    }
    return text
}

func singleTextSummary(in result: ToolResultMessage) -> String? {
    guard result.contentSummary.count == 1,
          case .text(let text) = result.contentSummary[0] else {
        return nil
    }
    return text
}

func nextApprovalCall(
    from iterator: inout TurnEventStream<AssistantMessage>.AsyncIterator,
) async throws -> PendingToolCall {
    while let event = try await iterator.next() {
        if case .toolApprovalRequired(let call) = event.kind {
            return call
        }
    }

    let missingCall: PendingToolCall? = nil
    return try #require(missingCall, "Expected toolApprovalRequired before stream completion")
}

func collectEvents(from turn: Turn<AssistantMessage>) async throws -> [AgentEvent<AssistantMessage>] {
    var events: [AgentEvent<AssistantMessage>] = []
    for try await event in turn.events {
        events.append(event)
    }
    return events
}

func assistantCompletions(in events: [AgentEvent<AssistantMessage>]) -> [String] {
    events.compactMap { event in
        guard case .result(let assistant) = event.kind else {
            return nil
        }
        return assistant.text
    }
}

extension AgentBehavior {
    static func test(_ systemPrompt: String = "Test") -> Self {
        .init(systemPrompt: systemPrompt)
    }
}
