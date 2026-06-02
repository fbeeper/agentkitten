// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation

/// A per-conversation session connected to Anthropic's Messages API.
///
/// Manages wire-format conversation history (`[AnthropicMessage]`) and drives a
/// manual agentic loop: when the model requests tool calls the session executes
/// them, appends results, and re-posts the full history until the model reaches
/// `end_turn` or `max_tokens`.
///
/// The API key is fetched from ``APIKeyProviding`` at the start of each operation.
///
/// In-flight request cancellation is owned by stream termination, not by
/// session deinitialization. The worker task retains the session while active,
/// so callers must stop iterating the returned stream to cancel the request.
public actor AnthropicInferenceSession: InferenceSession {
    let credentials: any APIKeyProviding
    let defaultModel: String
    let systemPrompt: String?
    let toolRuntime: ToolRuntime
    let tools: [AnthropicTool]
    let clientFactory: @Sendable (String) -> any AnthropicHTTPStreaming
    let historyRenderingConfiguration: HistoryRenderingConfiguration
    let structuredOutputInstructionFormat: String
    let maxEmptyToolUseFollowUps: Int
    var currentModel: String
    var resolvedContextSizes: [String: Int] = [:]
    var history: [AnthropicMessage]
    var cachedContextTokens: Int?
    let operationGate = SingleFlightOperationGate<InferenceSessionOperationKind> {
        InferenceError.concurrentOperationInProgress(active: $0)
    }

    init(
        credentials: any APIKeyProviding,
        defaultModel: String,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        initialHistory: [AnthropicMessage] = [],
        maxEmptyToolUseFollowUps: Int = 8,
        historyRenderingConfiguration: HistoryRenderingConfiguration = HistoryRenderingConfiguration(),
        structuredOutputInstructionFormat: String = AnthropicInferenceProvider.defaultStructuredOutputInstructionFormat,
        clientFactory: @escaping @Sendable (String) -> any AnthropicHTTPStreaming = { AnthropicHTTPClient(apiKey: $0) },
    ) {
        self.credentials = credentials
        self.defaultModel = defaultModel
        self.systemPrompt = systemPrompt
        self.toolRuntime = toolRuntime
        let rationaleDescription = toolRuntime.rationaleSchemaDescription
        tools = toolRuntime.allTools.map {
            AnthropicToolBridge.anthropicTool(from: $0, rationaleDescription: rationaleDescription)
        }
        history = initialHistory
        self.maxEmptyToolUseFollowUps = maxEmptyToolUseFollowUps
        self.historyRenderingConfiguration = historyRenderingConfiguration
        self.structuredOutputInstructionFormat = structuredOutputInstructionFormat
        currentModel = defaultModel
        self.clientFactory = clientFactory
    }

    /// Returns a snapshot of the current conversation history, captured under actor isolation.
    func captureHistory() -> [AnthropicMessage] {
        history
    }

    /// Runs a single inference turn and streams the model's response.
    public func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        let lease = try operationGate.begin(.run)
        let key: String
        do {
            key = try await apiKey()
        } catch {
            lease.end()
            throw error
        }
        // Multi-user: add `name: message.sender.description` to AnthropicMessage.
        // The Anthropic API surfaces the name field to the model as speaker context —
        // the right primitive for distinguishing participants without prompt hacks.
        // Only worth setting when the conversation has more than one participant.
        let userMessage = AnthropicMessage(role: .user, content: [.text(message.text)])

        let (stream, continuation) = InferenceStream.makeStream()
        let task = Task {
            await runTurn(
                userMessage: userMessage,
                apiKey: key,
                parameters: parameters,
                continuation: continuation,
            )
        }
        continuation.onTermination = { _ in
            lease.end()
            task.cancel()
        }
        return stream
    }

    // MARK: - Private

    private func runTurn(
        userMessage: AnthropicMessage,
        apiKey: String,
        parameters: InferenceRequestParameters,
        continuation: InferenceStream.Continuation,
    ) async {
        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
            toolStepBudget: parameters.toolStepBudget,
            context: parameters.toolExecutionContext,
            toolSelection: parameters.toolSelection,
        )
        let client = clientFactory(apiKey)
        // Snapshot history + the new user message into a local buffer.
        // self.history is only updated on success; cancellation and errors
        // leave it unchanged so aborted turns are invisible to future sends.
        var turnHistory = history + [userMessage]
        do {
            var stopReason = "end_turn"
            var toolUseResponsesSeen = 0 // Tracks consecutive empty tool call cycles. Orthogonal to per-call budget.
            repeat {
                try Task.checkCancellation()
                // Allow one follow-up after budget exhaustion so the model sees the
                // step-limit-exceeded error result. Break before a second such round
                // to avoid looping forever if the model keeps requesting tools.
                let wasExhaustedAtStart = await toolTurnRuntime.isBudgetExhausted
                let outcome = try await runSingleRequest(
                    client: client,
                    parameters: parameters,
                    toolTurnRuntime: toolTurnRuntime,
                    turnHistory: &turnHistory,
                    continuation: continuation,
                )
                stopReason = stopReasonAfterRequest(
                    stopReason: outcome.stopReason,
                    hasToolCalls: outcome.hasToolCalls,
                    toolUseResponsesSeen: &toolUseResponsesSeen,
                )
                if wasExhaustedAtStart { break }
            } while stopReason == "tool_use"

            history = turnHistory
            continuation.yield(
                .result(
                    extractAssistantText(from: turnHistory),
                    finishReason(from: stopReason),
                ),
            )
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private struct RequestOutcome {
        let stopReason: String
        let hasToolCalls: Bool
    }

    /// Sends one HTTP request, streams events, appends to `turnHistory`, and returns the stop reason.
    private func runSingleRequest(
        client: any AnthropicHTTPStreaming,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [AnthropicMessage],
        continuation: InferenceStream.Continuation,
    ) async throws -> RequestOutcome {
        let request = buildRequest(from: turnHistory, parameters: parameters)
        var textAccumulated = ""
        var pendingCalls: [PendingSSEToolCall] = []
        var stopReason = "end_turn"

        for try await event in client.stream(request: request) {
            try Task.checkCancellation()
            switch event {
            case .textDelta(let chunk):
                continuation.yield(.delta(chunk))
                textAccumulated += chunk
            case .toolCallReady(let id, let name, let argsJSON):
                pendingCalls.append(PendingSSEToolCall(id: id, name: name, argsJSON: argsJSON))
            case .stopReason(let reason):
                stopReason = reason
            case .usage(let total):
                // Anthropic is stateless: every request re-sends the full message array,
                // so `total` already covers the entire conversation history. Replace rather
                // than accumulate — accumulating would double-count all prior messages.
                cachedContextTokens = total
            case .error(let message):
                throw InferenceError.invalidResponse(message)
            }
        }

        // Only treat pending calls as executable when the model explicitly finished with tool_use.
        // A max_tokens finish may carry completed tool blocks that must be discarded.
        let callsToExecute = stopReason == "tool_use" ? pendingCalls : []
        appendAssistantTurn(text: textAccumulated, toolCalls: callsToExecute, to: &turnHistory)
        await executeToolCalls(
            callsToExecute,
            toolTurnRuntime: toolTurnRuntime,
            turnHistory: &turnHistory,
            emit: { continuation.yield($0) },
        )
        return RequestOutcome(stopReason: stopReason, hasToolCalls: !callsToExecute.isEmpty)
    }

    func appendAssistantTurn(
        text: String,
        toolCalls: [PendingSSEToolCall],
        to turnHistory: inout [AnthropicMessage],
    ) {
        var content: [AnthropicContent] = []
        if !text.isEmpty {
            content.append(.text(text))
        }
        for call in toolCalls {
            let inputValue: InferenceProviderJSONValue = jsonValue(from: call.argsJSON)
            content.append(.toolUse(id: call.id, name: call.name, input: inputValue))
        }
        if !content.isEmpty {
            turnHistory.append(AnthropicMessage(role: .assistant, content: content))
        }
    }

    /// Parse argsJSON once here; fall back to an empty object so history
    /// re-encoding never throws if the model emitted malformed JSON.
    private func jsonValue(from argsJSONString: String) -> InferenceProviderJSONValue {
        if let data = argsJSONString.data(using: .utf8),
           let value = try? JSONDecoder().decode(InferenceProviderJSONValue.self, from: data) {
            value
        } else {
            .object([:])
        }
    }

    func executeToolCalls<Output: Sendable>(
        _ calls: [PendingSSEToolCall],
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [AnthropicMessage],
        emit: @escaping @Sendable (InferenceEvent<Output>) -> Void,
    ) async {
        guard !calls.isEmpty else { return }
        var toolResultContents: [AnthropicContent] = []
        for call in calls {
            let result = await executeSingleTool(
                call,
                toolTurnRuntime: toolTurnRuntime,
                emit: emit,
            )
            toolResultContents.append(result)
        }
        turnHistory.append(AnthropicMessage(role: .user, content: toolResultContents))
    }

    private func executeSingleTool<Output: Sendable>(
        _ call: PendingSSEToolCall,
        toolTurnRuntime: ToolTurnRuntime,
        emit: @escaping @Sendable (InferenceEvent<Output>) -> Void,
    ) async -> AnthropicContent {
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
            emit(.toolCallCompleted(id: callID, name: call.name, outcome: .success(content: content)))
            return .toolResult(toolUseID: callID, content: content, isError: false)
        case .failure(let failure):
            emit(.toolCallCompleted(id: callID, name: call.name, outcome: .failure(failure)))
            return .toolResult(toolUseID: callID, content: [.text(failure.resultJSON)], isError: true)
        }
    }

    private func extractAssistantText(from turnHistory: [AnthropicMessage]) -> String {
        guard let lastAssistant = turnHistory.last(where: { $0.role == .assistant }) else {
            return ""
        }
        let textSegments = lastAssistant.content.compactMap { content -> String? in
            guard case .text(let text) = content else {
                return nil
            }
            return text
        }
        return textSegments.joined()
    }
}
#endif
