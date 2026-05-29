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
        let effectiveCalls: [OpenAIWireToolCall]? = wireCalls.isEmpty ? nil : wireCalls
        // Important: an empty `stop` response is still a completed assistant turn.
        // Keep `content: ""` so later user messages do not erase that turn from provider history.
        let effectiveText = text.isEmpty && effectiveCalls != nil ? nil : text
        turnHistory.append(OpenAIMessage.assistant(text: effectiveText, toolCalls: effectiveCalls))
    }

    /// Executes each model-requested tool call in order, appending a tool-result message per call.
    func executeToolCalls<Output: Sendable>(
        _ calls: [PendingOpenAIToolCall],
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        emit: @escaping @Sendable (InferenceEvent<Output>) -> Void,
    ) async {
        guard !calls.isEmpty else { return }
        for call in calls {
            let toolMessage = await executeSingleTool(
                call,
                toolTurnRuntime: toolTurnRuntime,
                emit: emit,
            )
            turnHistory.append(toolMessage)
        }
    }

    private func executeSingleTool<Output: Sendable>(
        _ call: PendingOpenAIToolCall,
        toolTurnRuntime: ToolTurnRuntime,
        emit: @escaping @Sendable (InferenceEvent<Output>) -> Void,
    ) async -> OpenAIMessage {
        let callID: ToolCallID = call.id
        let (rationale, argsJSON) = ToolRationale.extracting(from: call.argsJSON)
        emit(.toolCallRequested(id: callID, name: call.name, argumentsJSON: argsJSON))
        let pending = PendingToolCall(id: callID, name: call.name, argumentsJSON: argsJSON, modelRationale: rationale)
        let outcome = await toolTurnRuntime.invoke(
            pending,
            onApprovalRequired: { pendingCall in
                emit(.toolApprovalRequired(call: pendingCall))
            },
            onHookFired: { emit(.toolHookFired($0)) },
        )
        switch outcome {
        case .success(let content):
            emit(.toolCallCompleted(
                id: callID,
                name: call.name,
                outcome: .success(content: content),
            ))
            return OpenAIMessage.toolResult(toolCallID: callID, content: content, isError: false)
        case .failure(let failure):
            emit(.toolCallCompleted(id: callID, name: call.name, outcome: .failure(failure)))
            return OpenAIMessage.toolResult(
                toolCallID: callID,
                content: [.text(failure.resultJSON)],
                isError: true,
            )
        }
    }
}
#endif
