// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation

/// A per-conversation session connected to an OpenAI Chat Completions API endpoint.
///
/// Manages wire-format conversation history (`[OpenAIMessage]`) and drives a
/// manual agentic loop: when the model requests tool calls the session executes
/// them, appends results, and re-posts the full history until the model reaches
/// `stop` or `length`.
///
/// Compatible with any OpenAI-spec endpoint including LM Studio.
/// The API key is fetched from ``APIKeyProviding`` at the start of the first
/// turn and cached for the session's lifetime.
public actor OpenAIInferenceSession: InferenceSession {
    let credentials: any APIKeyProviding
    let defaultModel: String
    let baseURL: URL
    let systemPrompt: String?
    let toolRuntime: ToolRuntime
    let tools: [OpenAITool]
    let clientFactory: @Sendable (String, URL) -> any OpenAIHTTPStreaming
    let historyRenderingConfiguration: HistoryRenderingConfiguration
    let structuredOutputInstructionFormat: String
    let maxEmptyToolUseFollowUps: Int
    var currentModel: String
    var history: [OpenAIMessage]
    var cachedContextTokens: Int?
    private var cachedKey: String?
    let operationGate = SingleFlightOperationGate<InferenceSessionOperationKind> {
        InferenceError.concurrentOperationInProgress(active: $0)
    }

    init(
        credentials: any APIKeyProviding,
        defaultModel: String,
        baseURL: URL,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        initialHistory: [OpenAIMessage] = [],
        maxEmptyToolUseFollowUps: Int = 8,
        historyRenderingConfiguration: HistoryRenderingConfiguration = HistoryRenderingConfiguration(),
        structuredOutputInstructionFormat: String = OpenAIInferenceProvider.defaultStructuredOutputInstructionFormat,
        clientFactory: @escaping @Sendable (String, URL) -> any OpenAIHTTPStreaming = {
            OpenAIHTTPClient(apiKey: $0, baseURL: $1)
        },
    ) {
        self.credentials = credentials
        self.defaultModel = defaultModel
        self.baseURL = baseURL
        self.systemPrompt = systemPrompt
        self.toolRuntime = toolRuntime
        let rationaleDescription = toolRuntime.rationaleSchemaDescription
        tools = toolRuntime.allTools.map {
            OpenAIToolBridge.openAITool(from: $0, rationaleDescription: rationaleDescription)
        }
        history = initialHistory
        self.maxEmptyToolUseFollowUps = maxEmptyToolUseFollowUps
        self.historyRenderingConfiguration = historyRenderingConfiguration
        self.structuredOutputInstructionFormat = structuredOutputInstructionFormat
        currentModel = defaultModel
        self.clientFactory = clientFactory
    }

    /// Returns a snapshot of the current conversation history, captured under actor isolation.
    func captureHistory() -> [OpenAIMessage] {
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
        let userMessage = OpenAIMessage.user(message.text)
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
        userMessage: OpenAIMessage,
        apiKey: String,
        parameters: InferenceRequestParameters,
        continuation: InferenceStream.Continuation,
    ) async {
        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
            toolStepBudget: parameters.toolStepBudget,
            context: parameters.toolExecutionContext,
            toolSelection: parameters.toolSelection,
        )
        let client = clientFactory(apiKey, baseURL)
        // Snapshot history + the new user message into a local buffer.
        // self.history is only updated on success; cancellation and errors
        // leave it unchanged so aborted turns are invisible to future sends.
        var turnHistory = history + [userMessage]
        do {
            var stopReason = "stop"
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
            } while stopReason == "tool_calls"

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
        client: any OpenAIHTTPStreaming,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        continuation: InferenceStream.Continuation,
    ) async throws -> String {
        let request = buildRequest(from: turnHistory, parameters: parameters)
        var textAccumulated = ""
        var pendingCalls: [PendingOpenAIToolCall] = []
        var stopReason = "stop"

        for try await event in client.stream(request: request) {
            try Task.checkCancellation()
            switch event {
            case .textDelta(let chunk):
                continuation.yield(.delta(chunk))
                textAccumulated += chunk
            case .toolCallReady(let id, let name, let argsJSON):
                pendingCalls.append(PendingOpenAIToolCall(id: id, name: name, argsJSON: argsJSON))
            case .stopReason(let reason):
                stopReason = reason
            case .usage(let total):
                // OpenAI is stateless: every request re-sends the full message array,
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

    func executeToolCalls(
        _ calls: [PendingOpenAIToolCall],
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        continuation: InferenceStream.Continuation,
    ) async throws {
        guard !calls.isEmpty else { return }
        for call in calls {
            let toolMessage = try await executeSingleTool(
                call,
                toolTurnRuntime: toolTurnRuntime,
                continuation: continuation,
            )
            turnHistory.append(toolMessage)
        }
    }

    private func executeSingleTool(
        _ call: PendingOpenAIToolCall,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: InferenceStream.Continuation,
    ) async throws -> OpenAIMessage {
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
            return OpenAIMessage.toolResult(toolCallID: callID, content: content, isError: false)
        case .failure(let failure):
            continuation.yield(.toolCallCompleted(id: callID, name: call.name, outcome: .failure(failure)))
            return OpenAIMessage.toolResult(
                toolCallID: callID,
                content: [.text(failure.resultJSON)],
                isError: true,
            )
        }
    }

    private func extractAssistantText(from turnHistory: [OpenAIMessage]) -> String {
        turnHistory.last(where: { $0.role == .assistant }).flatMap {
            guard case .text(let text) = $0.content else { return nil }
            return text
        } ?? ""
    }
}
#endif
