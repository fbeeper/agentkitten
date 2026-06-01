// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

extension OpenAIInferenceSession {
    /// Appends the assistant turn (text and/or requested tool calls) to `turnHistory`.
    func appendAssistantTurn(
        text: String,
        toolCalls: [PendingOpenAIToolCall],
        to turnHistory: inout [OpenAIMessage],
    ) {
        let wireCalls: [OpenAIWireToolCall] = toolCalls.map {
            OpenAIWireToolCall(
                id: $0.id,
                type: "function",
                function: OpenAIWireToolCall.FunctionCall(name: $0.name, arguments: $0.argsJSON),
            )
        }
        let effectiveText = text.isEmpty ? nil : text
        let effectiveCalls: [OpenAIWireToolCall]? = wireCalls.isEmpty ? nil : wireCalls
        guard effectiveText != nil || effectiveCalls != nil else { return }
        turnHistory.append(OpenAIMessage.assistant(text: effectiveText, toolCalls: effectiveCalls))
    }

    /// Executes each model-requested tool call in order, appending a tool-result message per call.
    ///
    /// Returns `true` if any call was rejected because the step budget was exhausted.
    /// The caller should break the tool loop when this happens — a model that keeps
    /// requesting tools after budget exhaustion would loop forever otherwise.
    func executeToolCalls(
        _ calls: [PendingOpenAIToolCall],
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        continuation: InferenceStream.Continuation,
    ) async throws -> Bool {
        guard !calls.isEmpty else { return false }
        var budgetExhausted = false
        for call in calls {
            let (toolMessage, exceeded) = try await executeSingleTool(
                call,
                toolTurnRuntime: toolTurnRuntime,
                continuation: continuation,
            )
            turnHistory.append(toolMessage)
            if exceeded { budgetExhausted = true }
        }
        return budgetExhausted
    }

    private func executeSingleTool(
        _ call: PendingOpenAIToolCall,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: InferenceStream.Continuation,
    ) async throws -> (OpenAIMessage, budgetExhausted: Bool) {
        let callID: ToolCallID = call.id
        let (rationale, argsJSON) = ToolRationale.extracting(from: call.argsJSON)
        continuation.yield(.toolCallRequested(id: callID, name: call.name, argumentsJSON: argsJSON))
        let pending = PendingToolCall(id: callID, name: call.name, argumentsJSON: argsJSON, modelRationale: rationale)
        let outcome = await toolTurnRuntime.invoke(
            pending,
            onApprovalRequired: { pendingCall in
                continuation.yield(.toolApprovalRequired(call: pendingCall))
            },
            onHookFired: { continuation.yield(.toolHookFired($0)) },
        )
        switch outcome {
        case .success(let content):
            continuation.yield(.toolCallCompleted(
                id: callID,
                name: call.name,
                outcome: .success(content: content),
            ))
            return (OpenAIMessage.toolResult(toolCallID: callID, content: content, isError: false), false)
        case .failure(let failure):
            continuation.yield(.toolCallCompleted(id: callID, name: call.name, outcome: .failure(failure)))
            return (
                OpenAIMessage.toolResult(
                    toolCallID: callID,
                    content: [.text(failure.resultJSON)],
                    isError: true,
                ),
                failure == .stepLimitExceeded,
            )
        }
    }
}
#endif
