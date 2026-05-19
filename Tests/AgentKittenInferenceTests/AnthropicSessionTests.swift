// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
@testable import AgentKittenInference
import Foundation
import Synchronization
import Testing

// MARK: - Mock HTTP client

/// Records how many times `stream(request:)` was called and returns pre-set
/// SSE event sequences in order.
final class MockHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private struct State {
        var queue: [[SSEEvent]]
        var callCount = 0
    }

    private let state: Mutex<State>

    var callCount: Int {
        state.withLock { $0.callCount }
    }

    init(responses: [[SSEEvent]]) {
        state = Mutex(State(queue: responses))
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        let events = state.withLock { state in
            state.callCount += 1
            return state.queue.isEmpty ? [] : state.queue.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

final class CapturingStructuredHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let capturedRequestState = Mutex<AnthropicRequest?>(nil)
    private let events: [SSEEvent]

    var capturedRequest: AnthropicRequest? {
        capturedRequestState.withLock { $0 }
    }

    init(events: [SSEEvent]) {
        self.events = events
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        capturedRequestState.withLock { $0 = request }
        let events = events
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

final class SequencedHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let clients: [any AnthropicHTTPStreaming]
    private let index = Mutex(0)

    init(clients: [any AnthropicHTTPStreaming]) {
        self.clients = clients
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        let clientIndex = index.withLock { value in
            defer { value += 1 }
            return value
        }
        let client = clients[clientIndex]
        return client.stream(request: request)
    }
}

// MARK: - Helpers

private func makeSession(
    toolExecutionPolicy: some ToolExecutionPolicy = AutoApprovePolicy(),
    maxEmptyToolUseFollowUps: Int = 8,
    clientFactory: @escaping @Sendable (String) -> any AnthropicHTTPStreaming,
) -> AnthropicInferenceSession {
    AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(executionPolicy: toolExecutionPolicy),
        maxEmptyToolUseFollowUps: maxEmptyToolUseFollowUps,
        clientFactory: clientFactory,
    )
}

// MARK: - Tests

private let budgetOneMessage = UserMessage(text: "Hi")
private let budgetOneParameters = InferenceRequestParameters(toolStepBudget: .budget(1))

/// With a one-step tool budget and a mock that returns one tool_use response then a text
/// response, the session must send the follow-up request and deliver the final text.
/// Before the > fix (when it was >=), the follow-up was skipped and the text was never received.
@Test func session_sendsFollowUpAfterExactlyMaxToolStepsCycles() async throws {
    let mock = MockHTTPClient(responses: [
        [.stopReason("tool_use")],
        [.textDelta("Final answer"), .stopReason("end_turn")],
    ])
    let session = makeSession { _ in mock }

    var text = ""
    for try await event in try await session.run(budgetOneMessage, parameters: budgetOneParameters) {
        if case .delta(let chunk) = event {
            text += chunk
        }
    }

    #expect(mock.callCount == 2, "Expected 2 HTTP requests: one tool cycle + one follow-up")
    #expect(text == "Final answer", "Expected the follow-up response text to be delivered")
}

/// With `maxEmptyToolUseFollowUps = 1` and a mock that returns two consecutive
/// tool_use responses, the session must terminate after the second request
/// without hanging or sending a third request.
@Test func session_terminatesWhenEmptyToolUseFollowUpsExceedLimit() async throws {
    let mock = MockHTTPClient(responses: [
        [.stopReason("tool_use")],
        [.stopReason("tool_use")],
        [.textDelta("Should not appear"), .stopReason("end_turn")],
    ])
    let session = makeSession(maxEmptyToolUseFollowUps: 1) { _ in mock }

    var text = ""
    for try await event in try await session.run(budgetOneMessage, parameters: budgetOneParameters) {
        if case .delta(let chunk) = event {
            text += chunk
        }
    }

    #expect(mock.callCount == 2, "Expected exactly 2 HTTP requests before budget enforced")
    #expect(text.isEmpty, "Expected no text when loop is force-terminated by budget")
}

/// With a one-step tool budget and a single response that contains two toolCallReady events,
/// the session must execute the first tool and report the second as stepLimitExceeded
/// without invoking the executor — even when the executor itself has an unlimited budget.
@Test func session_enforcesMaxToolStepsAcrossIndividualCallsInOneResponse() async throws {
    let mock = MockHTTPClient(responses: [
        [
            .toolCallReady(id: "call-1", name: "tool_a", argsJSON: "{}"),
            .toolCallReady(id: "call-2", name: "tool_b", argsJSON: "{}"),
            .stopReason("tool_use"),
        ],
        [.textDelta("Done"), .stopReason("end_turn")],
    ])
    let session = makeSession { _ in mock }

    var completedOutcomes: [String: ToolCallOutcome] = [:]
    for try await event in try await session.run(budgetOneMessage, parameters: budgetOneParameters) {
        if case .toolCallCompleted(let id, _, let outcome) = event {
            completedOutcomes[id] = outcome
        }
    }

    #expect(mock.callCount == 2, "Expected follow-up request after the tool cycle")
    #expect(completedOutcomes["call-1"] != nil, "First tool call must produce a completed event")
    #expect(completedOutcomes["call-2"] != nil, "Second tool call must produce a completed event")
    if case .failure(let failure) = completedOutcomes["call-2"] {
        #expect(failure == .stepLimitExceeded, "Second call must be rejected as stepLimitExceeded")
    } else {
        Issue.record("Expected call-2 outcome to be .failure(.stepLimitExceeded)")
    }
}

struct StructuredDecision: Codable, Sendable, JSONSchemaProviding, Equatable {
    let answer: String

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "answer": .string(description: "The structured answer"),
            ],
            required: ["answer"],
        )
    }
}

struct InferenceEchoTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let message: String
    }

    struct Output: Codable, Sendable {
        let echo: String
    }

    static let name = "echo"
    static let defaultDescription = "Echoes the provided message."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["message": .string(description: "Message to echo.")],
            required: ["message"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(echo: arguments.message)
    }
}

private struct InferenceImageTool: RichAgentTool {
    struct Arguments: Codable, Sendable {
        let message: String
    }

    static let name = "image_echo"
    static let defaultDescription = "Returns text and image content."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["message": .string(description: "Message to echo.")],
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

@Test func session_alsoConformsToStructuredInferenceSession() {
    let session: any StructuredInferenceSession = makeSession { _ in
        MockHTTPClient(responses: [])
    }

    #expect(type(of: session) == AnthropicInferenceSession.self)
}

@Test func session_generateDecodesStructuredJSON() async throws {
    let client = CapturingStructuredHTTPClient(events: [
        .textDelta(#"{"answer":"structured"}"#),
        .stopReason("end_turn"),
    ])
    let session = makeSession { _ in client }

    let value: StructuredDecision = try await session.generate(
        prompt: "Return a structured answer",
        parameters: InferenceRequestParameters(),
    )
    #expect(value == StructuredDecision(answer: "structured"))

    let request = try #require(client.capturedRequest)
    #expect(request.tools == nil)
    #expect(request.temperature == 0)
}

@Test func session_generateSupportsToolCallsBeforeFinalStructuredJSON() async throws {
    let client = CapturingStructuredHTTPClient(events: [
        .toolCallReady(id: "call-1", name: "echo", argsJSON: #"{"message":"structured"}"#),
        .stopReason("tool_use"),
    ])
    let followUp = CapturingStructuredHTTPClient(events: [
        .textDelta(#"{"answer":"structured"}"#),
        .stopReason("end_turn"),
    ])
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(InferenceEchoTool())]),
    )
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(
            registry: executor.registry,
            executionPolicy: AutoApprovePolicy(),
        ),
        clientFactory: { _ in SequencedHTTPClient(clients: [client, followUp]) },
    )

    let value: StructuredDecision =
        try await session.generate(
            prompt: "Return a structured answer", parameters: InferenceRequestParameters(),
        )
    #expect(value == StructuredDecision(answer: "structured"))

    let firstRequest = try #require(client.capturedRequest)
    #expect(firstRequest.tools?.isEmpty == false)
}

@Test func session_generateStreamEmitsStructuredToolEvents() async throws {
    let client = CapturingStructuredHTTPClient(events: [
        .toolCallReady(id: "call-1", name: "echo", argsJSON: #"{"message":"structured"}"#),
        .stopReason("tool_use"),
    ])
    let followUp = CapturingStructuredHTTPClient(events: [
        .textDelta(#"{"answer":"structured"}"#),
        .stopReason("end_turn"),
    ])
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(InferenceEchoTool())]),
    )
    let session = AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(
            registry: executor.registry,
            executionPolicy: AutoApprovePolicy(),
        ),
        clientFactory: { _ in SequencedHTTPClient(clients: [client, followUp]) },
    )

    let stream: StructuredInferenceStream<StructuredDecision> =
        try await session.generateStream(
            prompt: "Return a structured answer", parameters: InferenceRequestParameters(),
        )
    let observation = try await observeStructuredToolStream(stream)

    #expect(observation.sawToolStart)
    #expect(observation.sawToolCompletion)
    #expect(observation.value == StructuredDecision(answer: "structured"))
}

private struct StructuredToolStreamObservation {
    let sawToolStart: Bool
    let sawToolCompletion: Bool
    let value: StructuredDecision?
}

private func observeStructuredToolStream(
    _ stream: StructuredInferenceStream<StructuredDecision>,
) async throws -> StructuredToolStreamObservation {
    var sawToolStart = false
    var sawToolCompletion = false
    var value: StructuredDecision?
    for try await event in stream {
        switch event {
        case .delta:
            Issue.record("Structured stream should not emit delta events")
        case .toolCallRequested(let id, let name, let argumentsJSON):
            sawToolStart = id == "call-1"
                && name == "echo"
                && argumentsJSON == #"{"message":"structured"}"#
        case .toolApprovalRequired:
            break
        case .toolCallCompleted(let id, let name, let outcome):
            if case .success(let content) = outcome {
                sawToolCompletion = id == "call-1"
                    && name == "echo"
                    && content == [.text(#"{"echo":"structured"}"#)]
            }
        case .result(let structured, let reason):
            #expect(reason == .endTurn)
            value = structured
        case .toolHookFired: break
        }
    }
    return StructuredToolStreamObservation(
        sawToolStart: sawToolStart,
        sawToolCompletion: sawToolCompletion,
        value: value,
    )
}

@Test func anthropicToolResult_encodesImageBlocksInArrayForm() throws {
    let content = AnthropicContent.toolResult(
        toolUseID: "call-1",
        content: [
            .text("Screenshot captured."),
            .image(mediaType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47])),
        ],
        isError: false,
    )
    let data = try JSONEncoder().encode(content)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let blocks = try #require(object["content"] as? [[String: Any]])
    #expect(object["type"] as? String == "tool_result")
    #expect(object["tool_use_id"] as? String == "call-1")
    #expect(blocks.count == 2)
    #expect(blocks[0]["type"] as? String == "text")
    #expect(blocks[0]["text"] as? String == "Screenshot captured.")
    let source = try #require(blocks[1]["source"] as? [String: Any])
    #expect(blocks[1]["type"] as? String == "image")
    #expect(source["type"] as? String == "base64")
    #expect(source["media_type"] as? String == "image/png")
    #expect(source["data"] as? String == Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())
}
