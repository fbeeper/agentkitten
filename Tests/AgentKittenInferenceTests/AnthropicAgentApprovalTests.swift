// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore
@testable import AgentKittenInference

private struct AgentAnthropicRequiresApprovalPolicy: ToolExecutionPolicy {
    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .requiresApproval
    }
}

private struct TestAnthropicInferenceProvider: InferenceProviding {
    typealias Session = AnthropicInferenceSession

    let clientFactory: @Sendable (String) -> any AnthropicHTTPStreaming

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext
    ) -> AnthropicInferenceSession {
        AnthropicInferenceSession(
            credentials: MockAPIKeyProvider("test-key"),
            defaultModel: "test-model",
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            clientFactory: clientFactory
        )
    }
}

@Suite("Anthropic Agent Approval")
struct AnthropicAgentApprovalTests {
    @Test func agentTurn_approvalRequiredResumesSameTurn() async throws {
        let mock = MockHTTPClient(responses: [
            [
                .toolCallReady(id: "call-1", name: "echo", argsJSON: #"{"message":"approved"}"#),
                .stopReason("tool_use"),
            ],
            [.textDelta("Done"), .stopReason("end_turn")],
        ])
        let session = makeAnthropicApprovalSession(clientFactory: { _ in mock })
        let turn = try await session.send("Hi")
        var iterator = turn.events.makeAsyncIterator()
        let approval = try await nextApprovalCall(from: &iterator)

        try await session.approve(callID: approval.id)

        var completion: ToolCallOutcome?
        var assistantMessages: [String] = []
        while let event = try await iterator.next() {
            switch event.kind {
            case .toolCallCompleted(let name, let id, let outcome):
                if name == InferenceEchoTool.name, id == approval.id {
                    completion = outcome
                }
            case .result(let assistant):
                assistantMessages.append(assistant.text)
            default:
                break
            }
        }

        #expect(mock.callCount == 2)
        guard case .success(let content) = try #require(completion) else {
            Issue.record("Expected approved tool call to succeed")
            return
        }
        #expect(singleTextContent(in: content) == #"{"echo":"approved"}"#)
        #expect(assistantMessages == ["Done"])
    }

    @Test func agentTurn_denialResumesSameTurn() async throws {
        let mock = MockHTTPClient(responses: [
            [
                .toolCallReady(id: "call-1", name: "echo", argsJSON: #"{"message":"denied"}"#),
                .stopReason("tool_use"),
            ],
            [.textDelta("Done"), .stopReason("end_turn")],
        ])
        let session = makeAnthropicApprovalSession(clientFactory: { _ in mock })
        let turn = try await session.send("Hi")
        var iterator = turn.events.makeAsyncIterator()
        let approval = try await nextApprovalCall(from: &iterator)

        try await session.deny(callID: approval.id, reason: "blocked")

        var completion: ToolCallOutcome?
        var assistantMessages: [String] = []
        while let event = try await iterator.next() {
            switch event.kind {
            case .toolCallCompleted(let name, let id, let outcome):
                if name == InferenceEchoTool.name, id == approval.id {
                    completion = outcome
                }
            case .result(let assistant):
                assistantMessages.append(assistant.text)
            default:
                break
            }
        }

        #expect(mock.callCount == 2)
        #expect(completion == .failure(.denied(reason: "blocked")))
        #expect(assistantMessages == ["Done"])
    }
}

private func makeAnthropicApprovalSession(
    clientFactory: @escaping @Sendable (String) -> any AnthropicHTTPStreaming
) -> AgentSession {
    let provider = TestAnthropicInferenceProvider(clientFactory: clientFactory)
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: InferenceProvider(provider)),
        behavior: .init(systemPrompt: "Test"),
        toolDefinition: ToolDefinition(
            tools: [AnyAgentTool(InferenceEchoTool())],
            executionPolicy: AgentAnthropicRequiresApprovalPolicy()
        ),
    )
    return agent.makeSession()
}
