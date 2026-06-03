// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation
import Testing

private struct AnthropicDenyAllPolicy: ToolExecutionPolicy {
    let reason: String

    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .deny(reason: reason)
    }
}

private struct AnthropicRequiresApprovalPolicy: ToolExecutionPolicy {
    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .requiresApproval
    }
}

@Test func session_deniedToolCallProducesFailureWithoutExecutingTool() async throws {
    let mock = MockHTTPClient(responses: [
        [
            .toolCallReady(id: "call-1", name: "echo", argsJSON: #"{"message":"blocked"}"#),
            .stopReason("tool_use"),
        ],
        [.textDelta("Done"), .stopReason("end_turn")],
    ])
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(InferenceEchoTool())]),
    )
    let session = AnthropicInferenceSession(
        client: mock,
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(
            registry: executor.registry,
            executionPolicy: AnthropicDenyAllPolicy(reason: "blocked"),
        ),
    )

    var outcome: ToolCallOutcome?
    for try await event in try await session.run(
        UserMessage(text: "Hi"),
        parameters: InferenceRequestParameters(toolStepBudget: .budget(1)),
    ) {
        if case .toolCallCompleted(let id, _, let completed) = event, id == "call-1" {
            outcome = completed
        }
    }

    #expect(outcome == .failure(.denied(reason: "blocked")))
}

@Test func session_generateStructuredToolDenialProducesFailureWithoutExecutingTool() async throws {
    let client = CapturingStructuredHTTPClient(events: [
        .toolCallReady(id: "call-1", name: "echo", argsJSON: #"{"message":"blocked"}"#),
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
        client: SequencedHTTPClient(clients: [client, followUp]),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(
            registry: executor.registry,
            executionPolicy: AnthropicDenyAllPolicy(reason: "blocked"),
        ),
    )

    let stream: StructuredInferenceStream<StructuredDecision> =
        try await session.generateStream(
            prompt: "Return a structured answer",
            parameters: InferenceRequestParameters(toolStepBudget: .budget(1)),
        )

    var outcome: ToolCallOutcome?
    for try await event in stream {
        if case .toolCallCompleted(let id, _, let completed) = event, id == "call-1" {
            outcome = completed
        }
    }

    #expect(outcome == .failure(.denied(reason: "blocked")))
}

@Test func session_deniedToolCallFeedsDeniedResultJSONBackToModelAsError() async throws {
    let first = CapturingStructuredHTTPClient(events: [
        .toolCallReady(id: "call-1", name: "echo", argsJSON: #"{"message":"blocked"}"#),
        .stopReason("tool_use"),
    ])
    let followUp = CapturingStructuredHTTPClient(events: [
        .textDelta("Done"),
        .stopReason("end_turn"),
    ])
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(InferenceEchoTool())]),
    )
    let session = AnthropicInferenceSession(
        client: SequencedHTTPClient(clients: [first, followUp]),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(
            registry: executor.registry,
            executionPolicy: AnthropicDenyAllPolicy(reason: "blocked"),
        ),
    )

    for try await _ in try await session.run(
        UserMessage(text: "Hi"),
        parameters: InferenceRequestParameters(toolStepBudget: .budget(1)),
    ) {}

    let request = try #require(followUp.capturedRequest)
    let userMessage = try #require(request.messages.last)
    #expect(userMessage.role == .user)
    let data = try JSONEncoder().encode(userMessage)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let content = try #require(object["content"] as? [[String: Any]])
    let toolResult = try #require(content.first)
    #expect(toolResult["type"] as? String == "tool_result")
    #expect(toolResult["tool_use_id"] as? String == "call-1")
    #expect(toolResult["is_error"] as? Bool == true)
    let blocks = try #require(toolResult["content"] as? [[String: Any]])
    #expect(blocks.count == 1)
    #expect(blocks[0]["type"] as? String == "text")
    #expect(
        blocks[0]["text"] as? String
            == ToolCallFailure.denied(reason: "blocked").resultJSON,
    )
}

@Test func session_approvalRequiredToolCallWaitsAndThenExecutesTool() async throws {
    let mock = MockHTTPClient(responses: [
        [
            .toolCallReady(id: "call-1", name: "echo", argsJSON: #"{"message":"approved"}"#),
            .stopReason("tool_use"),
        ],
        [.textDelta("Done"), .stopReason("end_turn")],
    ])
    let gate = ToolApprovalGate()
    let session = AnthropicInferenceSession(
        client: mock,
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: {
            let toolBehavior = ToolBehavior()
            return ToolRuntime(
                toolDefinition: ToolDefinition(
                    tools: [AnyAgentTool(InferenceEchoTool())],
                    executionPolicy: AnthropicRequiresApprovalPolicy(),
                ),
                toolBehavior: toolBehavior,
                approvalGate: gate,
            )
        }(),
    )

    var sawApproval = false
    var outcome: ToolCallOutcome?
    for try await event in try await session.run(
        UserMessage(text: "Hi"),
        parameters: InferenceRequestParameters(toolStepBudget: .budget(1)),
    ) {
        switch event {
        case .toolApprovalRequired(let call):
            sawApproval = true
            try await gate.approve(callID: call.id)
        case .toolCallCompleted(let id, _, let completed):
            if id == "call-1" {
                outcome = completed
            }
        default:
            break
        }
    }

    #expect(sawApproval)
    guard case .success(let content) = try #require(outcome) else {
        Issue.record("Expected approved tool call to succeed")
        return
    }
    #expect(singleTextContent(in: content) == #"{"echo":"approved"}"#)
}
#endif
