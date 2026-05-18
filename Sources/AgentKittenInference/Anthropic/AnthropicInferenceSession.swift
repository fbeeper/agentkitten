// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
import Foundation

/// A per-conversation session connected to Anthropic's Messages API.
///
/// Manages wire-format conversation history (`[AnthropicMessage]`) and drives a
/// manual agentic loop: when the model requests tool calls the session executes
/// them, appends results, and re-posts the full history until the model reaches
/// `end_turn` or `max_tokens`.
///
/// The API key is fetched from ``APIKeyProviding`` at the start of the first turn
/// and cached for the session's lifetime.
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
    private let maxEmptyToolUseFollowUps: Int
    private var currentModel: String
    private var resolvedContextSizes: [String: Int] = [:]
    var history: [AnthropicMessage]
    var cachedContextTokens: Int?
    private var cachedKey: String?
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
        historyRenderingConfiguration: HistoryRenderingConfiguration = .init(),
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
            key = try await resolvedKey()
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
        // Unstructured Task: onTermination is a @Sendable sync callback; cannot await.
        continuation.onTermination = { _ in
            lease.end()
            task.cancel()
        }
        return stream
    }

    // MARK: - Private

    func resolvedKey() async throws -> String {
        if let cached = cachedKey {
            return cached
        }
        let key = try await credentials.apiKey()
        cachedKey = key
        return key
    }

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
            var toolUseResponsesSeen = 0
            repeat {
                try Task.checkCancellation()
                stopReason = try await runSingleRequest(
                    client: client,
                    parameters: parameters,
                    toolTurnRuntime: toolTurnRuntime,
                    turnHistory: &turnHistory,
                    continuation: continuation,
                )
                stopReason = stopReasonAfterRequest(
                    stopReason: stopReason,
                    toolUseResponsesSeen: &toolUseResponsesSeen,
                )
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

    /// Sends one HTTP request, streams events, appends to `turnHistory`, and returns the stop reason.
    private func runSingleRequest(
        client: any AnthropicHTTPStreaming,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [AnthropicMessage],
        continuation: InferenceStream.Continuation,
    ) async throws -> String {
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

        appendAssistantTurn(text: textAccumulated, toolCalls: pendingCalls, to: &turnHistory)
        try await executeToolCalls(
            pendingCalls,
            toolTurnRuntime: toolTurnRuntime,
            turnHistory: &turnHistory,
            continuation: continuation,
        )
        return stopReason
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
            // Parse argsJSON once here; fall back to an empty object so history
            // re-encoding never throws if the model emitted malformed JSON.
            let inputValue: AnthropicJSONValue = if let data = call.argsJSON.data(using: .utf8),
                                                    let raw = try? JSONSerialization.jsonObject(with: data) {
                AnthropicJSONValue(raw)
            } else {
                .object([:])
            }
            content.append(.toolUse(id: call.id, name: call.name, input: inputValue))
        }
        if !content.isEmpty {
            turnHistory.append(AnthropicMessage(role: .assistant, content: content))
        }
    }

    func executeToolCalls(
        _ calls: [PendingSSEToolCall],
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [AnthropicMessage],
        continuation: InferenceStream.Continuation,
    ) async throws {
        guard !calls.isEmpty else { return }
        var toolResultContents: [AnthropicContent] = []
        for call in calls {
            let result = try await executeSingleTool(call, toolTurnRuntime: toolTurnRuntime, continuation: continuation)
            toolResultContents.append(result)
        }
        turnHistory.append(AnthropicMessage(role: .user, content: toolResultContents))
    }

    private func executeSingleTool(
        _ call: PendingSSEToolCall,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: InferenceStream.Continuation,
    ) async throws -> AnthropicContent {
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
            return .toolResult(toolUseID: callID, content: content, isError: false)
        case .failure(let failure):
            continuation.yield(.toolCallCompleted(id: callID, name: call.name, outcome: .failure(failure)))
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

extension AnthropicInferenceSession {
    public func contextUsage() async throws -> ContextUsage {
        let lease = try operationGate.begin(.contextUsage)
        defer {
            lease.end()
        }
        return try await uncheckedContextUsage()
    }

    /// Returns context usage for the session's current Anthropic history without acquiring
    /// ``operationGate``.
    ///
    /// This exists so callers that already hold a different lease, such as
    /// `compactContext(options:)`, can reuse the same token-counting logic without
    /// re-entering the single-flight guard and tripping the concurrency error on
    /// themselves.
    func uncheckedContextUsage() async throws -> ContextUsage {
        let contextSize = await resolveContextSize(for: currentModel)
        if history.isEmpty {
            return ContextUsage(contextTokens: 0, contextSize: contextSize)
        }
        if let cached = cachedContextTokens {
            return ContextUsage(contextTokens: cached, contextSize: contextSize)
        }
        let key = try await resolvedKey()
        let request = AnthropicCountTokensRequest(
            model: currentModel,
            system: systemPrompt,
            messages: history,
            tools: tools.isEmpty ? nil : tools,
        )
        let count = try await clientFactory(key).countTokens(request: request)
        cachedContextTokens = count
        return ContextUsage(contextTokens: count, contextSize: contextSize)
    }

    private func resolveContextSize(for model: String) async -> Int? {
        if let cached = resolvedContextSizes[model] {
            return cached
        }

        let fallback = AnthropicModelContextWindow.standardMaxInputTokens(for: model)
        guard let key = try? await resolvedKey() else {
            return fallback
        }

        do {
            let client = clientFactory(key)
            if let resolved = try await client.maxInputTokens(for: model), resolved > 0 {
                resolvedContextSizes[model] = resolved
                return resolved
            }
        } catch {
            return fallback
        }

        return fallback
    }

    func buildRequest(
        from turnHistory: [AnthropicMessage],
        parameters: InferenceRequestParameters,
    ) -> AnthropicRequest {
        let effectiveTools: [AnthropicTool]?
        let selectedTools = tools.filter {
            parameters.toolSelection.allows(toolName: $0.name)
        }
        effectiveTools = selectedTools.isEmpty ? nil : selectedTools
        let model = parameters.inferenceContext[AnthropicModelKey.self] ?? defaultModel
        currentModel = model
        return AnthropicRequest(
            model: model,
            maxTokens: parameters.configuration.maxTokens,
            system: systemPrompt,
            messages: turnHistory,
            tools: effectiveTools,
            stream: true,
            temperature: parameters.configuration.temperature,
        )
    }

    func stopReasonAfterRequest(
        stopReason: String,
        toolUseResponsesSeen: inout Int,
    ) -> String {
        guard stopReason == "tool_use" else {
            return stopReason
        }
        toolUseResponsesSeen += 1
        // Anthropic can return repeated `tool_use` stop reasons without yielding any
        // executable tool calls. We cap those follow-up cycles separately from
        // per-call execution budgeting, which is enforced in `executeToolCalls`.
        if toolUseResponsesSeen > maxEmptyToolUseFollowUps {
            return "end_turn"
        }
        return "tool_use"
    }

    func finishReason(from stopReason: String) -> FinishReason {
        switch stopReason {
        case "max_tokens":
            .maxTokens
        case "end_turn":
            .endTurn
        case "cancelled":
            .cancelled
        default:
            .endTurn
        }
    }
}
