// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

private struct CodableTraceValue: Codable, Equatable {
    let answer: String
}

@Suite("AgentTrace Codable")
struct TraceCodableTests {
    @Test func traceEntryKindCodable_roundTripsAllCases() throws {
        let kinds = try allTraceKinds()

        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(AgentTraceEntry.Kind.self, from: data)
            #expect(decoded == kind)
        }
    }

    @Test func traceKindsAndEntries_areHashable() throws {
        let kindSet: Set<AgentTraceEntry.Kind> = [
            .structuredResult(
                type: structuredResultTypeLabel(for: CodableTraceValue.self),
                json: try structuredResultJSON(for: CodableTraceValue(answer: "Goal")),
            ),
            executionPreparationKind(),
            .conversationResolved(AgentTraceEntry.Kind.ConversationResolvedInfo(
                identity: ConversationIdentitySnapshot(
                    conversationID: "conversation-2",
                    inferenceSessionID: "inference-2",
                ),
                resolutionKind: .replace,
            )),
            contextCompactionKind(mode: .manual),
            .validation(.init(
                result: .feedback,
                message: "Try again",
                validator: "HashableValidator",
            )),
            .toolApprovalRequired(approvalRequiredInfo()),
            .turnCompleted(.completed),
        ]
        #expect(kindSet.count == 7)

        let entrySet: Set<AgentTraceEntry> = [
            AgentTraceEntry(
                kind: .structuredResult(
                    type: structuredResultTypeLabel(for: CodableTraceValue.self),
                    json: try structuredResultJSON(for: CodableTraceValue(answer: "ok")),
                ),
                timestamp: AgentTraceEntry.Timestamp(),
                invocationID: .generate(),
            ),
            AgentTraceEntry(
                kind: .turnCompleted(.completed),
                timestamp: AgentTraceEntry.Timestamp(),
                invocationID: .generate(),
            ),
        ]
        #expect(entrySet.count == 2)
    }

    @Test func agentErrorCodable_roundTripsAndPreservesDescription() throws {
        let source = InferenceError.invalidResponse("boom")
        let error = AgentTraceEntry.Kind.ErrorInfo(source)
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(AgentTraceEntry.Kind.ErrorInfo.self, from: data)

        #expect(decoded == error)
        #expect(decoded.description == String(describing: source))
        let asError: any Error = decoded
        #expect(
            String(describing: asError)
                == "ErrorInfo(description: \"invalidResponse(\\\"boom\\\")\")",
        )
    }

    @Test func agentTurnOutcomeCodable_roundTripsAllCases() throws {
        let outcomes: [AgentTraceEntry.Kind.TurnOutcome] = [
            .completed,
            .cancelled,
            .failed(AgentTraceEntry.Kind.ErrorInfo(description: "boom")),
        ]

        for outcome in outcomes {
            let data = try JSONEncoder().encode(outcome)
            let decoded = try JSONDecoder().decode(AgentTraceEntry.Kind.TurnOutcome.self, from: data)
            #expect(decoded == outcome)
        }
    }
}

private func executionPreparationKind() -> AgentTraceEntry.Kind {
    .executionPreparation(AgentTraceEntry.Kind.ExecutionPreparationInfo(
        verdict: .rebuildSession,
        provider: .default,
        toolSelection: .all,
        toolStepBudget: .budget(20),
        inferenceConfiguration: InferenceConfigurationSnapshot(
            temperature: 0.7,
            maxTokens: 4096,
        ),
        inferenceContext: CustomContextSnapshot(entries: [
            .init(key: "AnthropicModelKey", valueSummary: "claude-opus-4-5"),
        ]),
        turnOverrides: TurnOverridesSnapshot(
            toolSelection: .disabled,
            toolStepBudget: nil,
            inferenceConfiguration: nil,
            provider: nil,
        ),
    ))
}

private func allTraceKinds() throws -> [AgentTraceEntry.Kind] {
    let assistantMessage = AgentMessage.assistant(AssistantMessage(text: "x"))
    let toolCallMessage = AgentMessage.toolCall(ToolCallMessage(
        id: "call-1",
        name: "echo",
        argumentsJSON: #"{"message":"x"}"#,
    ))
    let toolResultMessage = AgentMessage.toolResult(ToolResultMessage(
        callID: "call-1",
        name: "echo",
        contentSummary: [.text(#"{"echo":"x"}"#)],
        isError: false,
    ))
    return [
        .turnStarted(UserMessage(text: "x")),
        .message(assistantMessage),
        .message(toolCallMessage),
        .message(toolResultMessage),
        .structuredResult(
            type: structuredResultTypeLabel(for: CodableTraceValue.self),
            json: try structuredResultJSON(for: CodableTraceValue(answer: "ok")),
        ),
        executionPreparationKind(),
        .conversationResolved(AgentTraceEntry.Kind.ConversationResolvedInfo(
            identity: ConversationIdentitySnapshot(
                conversationID: "conversation-1",
                inferenceSessionID: "inference-1",
            ),
            resolutionKind: .rebuildSession,
        )),
        contextCompactionKind(mode: .automatic),
        .stateMutation(.init(
            operation: .set,
            key: "topic",
            valueType: "string",
        )),
        approvalRequiredKind(),
        .validation(.init(
            result: .feedback,
            message: "Try again",
            validator: "CodableValidator",
        )),
        .error(AgentTraceEntry.Kind.ErrorInfo(description: "boom")),
        .turnCompleted(.completed),
    ]
}

private func approvalPendingToolCall() -> PendingToolCall {
    PendingToolCall(
        id: "call-1",
        name: "echo",
        argumentsJSON: #"{"message":"x"}"#,
    )
}

private func approvalRequiredInfo() -> AgentTraceEntry.Kind.ToolApprovalRequiredInfo {
    .init(
        call: approvalPendingToolCall(),
        context: CustomContextSnapshot(entries: [
            .init(key: "toolApprovalReason", valueSummary: "blocked by policy"),
        ]),
    )
}

private func approvalRequiredKind() -> AgentTraceEntry.Kind {
    .toolApprovalRequired(approvalRequiredInfo())
}

private func contextCompactionKind(
    mode: AgentTraceEntry.Kind.ContextCompactionInfo.Mode,
) -> AgentTraceEntry.Kind {
    .contextCompaction(.init(
        mode: mode,
        provider: .named("CompactionProvider"),
        inferenceConfiguration: InferenceConfigurationSnapshot(
            temperature: 0.2,
            maxTokens: 256,
        ),
        inferenceContext: CustomContextSnapshot(entries: [
            .init(key: "AnthropicModelKey", valueSummary: "claude-opus-4-5"),
            .init(key: "SentinelContextKey", valueSummary: "sentinel-value"),
        ]),
        result: .compacted(.init(
            usageBefore: .init(contextTokens: 80, contextSize: 100),
            usageAfter: .init(contextTokens: 20, contextSize: 100),
        )),
    ))
}
