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
/// them through the ``ToolRuntime``, appends results, and re-posts the full
/// history until the model reaches `stop` or `length`.
///
/// Compatible with any OpenAI-spec endpoint including LM Studio.
///
/// This session does not yet support token counting or context compaction; those
/// capabilities are layered on by later extensions.
public actor OpenAIInferenceSession: InferenceSession {
    let client: any OpenAIHTTPStreaming
    let defaultModel: String
    let systemPrompt: String?
    let toolRuntime: ToolRuntime
    let tools: [OpenAITool]
    var currentModel: String
    var history: [OpenAIMessage]
    let structuredOutputInstructionFormat: String
    var resolvedContextSizes: [String: Int] = [:]
    var cachedContextTokens: Int?
    let operationGate = SingleFlightOperationGate<InferenceSessionOperationKind> {
        InferenceError.concurrentOperationInProgress(active: $0)
    }

    init(
        client: any OpenAIHTTPStreaming,
        defaultModel: String,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        initialHistory: [OpenAIMessage] = [],
        structuredOutputInstructionFormat: String = OpenAIInferenceProvider.defaultStructuredOutputInstructionFormat,
    ) {
        self.client = client
        self.defaultModel = defaultModel
        self.systemPrompt = systemPrompt
        self.toolRuntime = toolRuntime
        let rationaleDescription = toolRuntime.rationaleSchemaDescription
        tools = toolRuntime.allTools.map {
            OpenAIToolBridge.openAITool(from: $0, rationaleDescription: rationaleDescription)
        }
        self.structuredOutputInstructionFormat = structuredOutputInstructionFormat
        history = initialHistory
        currentModel = defaultModel
    }

    /// Returns a snapshot of the current conversation history, captured under actor isolation.
    func captureHistory() -> [OpenAIMessage] {
        history
    }

    /// Runs a single inference turn and streams the model's response.
    public func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        let lease = try operationGate.begin(.run)
        let userMessage = OpenAIMessage.user(message.text)
        let (stream, continuation) = InferenceStream.makeStream()
        let task = Task {
            await runTurn(userMessage: userMessage, parameters: parameters, continuation: continuation)
        }
        continuation.onTermination = { _ in
            lease.end()
            task.cancel()
        }
        return stream
    }

    // MARK: - Private

    private func runTurn(
        userMessage: OpenAIMessage,
        parameters: InferenceRequestParameters,
        continuation: InferenceStream.Continuation,
    ) async {
        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
            toolStepBudget: parameters.toolStepBudget,
            context: parameters.toolExecutionContext,
            toolSelection: parameters.toolSelection,
        )
        // Snapshot history + the new user message into a local buffer.
        // self.history is only updated on success; cancellation and errors
        // leave it unchanged so aborted turns are invisible to future sends.
        var turnHistory = history + [userMessage]
        do {
            var stopReason = "stop"
            var hasToolCalls = false
            var lastResponseText = ""
            repeat {
                try Task.checkCancellation()
                guard await toolTurnRuntime.prepareRound() else {
                    break // Given the follow up stopReason is ok on tool_calls without having to set manually.
                }
                let outcome = try await runSingleRequest(
                    client: client,
                    parameters: parameters,
                    toolTurnRuntime: toolTurnRuntime,
                    turnHistory: &turnHistory,
                    continuation: continuation,
                )
                stopReason = outcome.stopReason
                hasToolCalls = outcome.hasToolCalls
                lastResponseText = outcome.text
                await toolTurnRuntime.recordRound()
            } while hasToolCalls

            history = turnHistory
            continuation.yield(
                .result(
                    lastResponseText,
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
        let text: String
        let hasToolCalls: Bool
    }

    /// Sends one HTTP request, streams events, appends to `turnHistory`, and returns request metadata.
    private func runSingleRequest(
        client: any OpenAIHTTPStreaming,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        continuation: InferenceStream.Continuation,
    ) async throws -> RequestOutcome {
        let request = buildRequest(from: turnHistory, parameters: parameters)
        var textAccumulated = ""
        var pendingCalls: [PendingOpenAIToolCall] = []
        var stopReason = "stop"

        for try await event in try await client.stream(request: request) {
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

        if stopReason == "tool_calls", pendingCalls.isEmpty {
            throw InferenceError.invalidResponse("OpenAI returned tool_calls finish reason without tool calls.")
        }
        // Only treat pending calls as executable when the model explicitly finished with tool_calls.
        // A length finish may carry partial or complete tool-call deltas that must be discarded.
        let callsToExecute = stopReason == "tool_calls" ? pendingCalls : []
        appendAssistantTurn(text: textAccumulated, toolCalls: callsToExecute, to: &turnHistory)
        await executeToolCalls(
            callsToExecute,
            toolTurnRuntime: toolTurnRuntime,
            turnHistory: &turnHistory,
            emit: { continuation.yield($0) },
        )
        return RequestOutcome(stopReason: stopReason, text: textAccumulated, hasToolCalls: !callsToExecute.isEmpty)
    }

    func buildRequest(
        from turnHistory: [OpenAIMessage],
        parameters: InferenceRequestParameters,
    ) -> OpenAIRequest {
        let selectedTools = tools.filter { parameters.toolSelection.allows(toolName: $0.function.name) }
        let effectiveTools: [OpenAITool]? = selectedTools.isEmpty ? nil : selectedTools
        let model = parameters.inferenceContext[OpenAIModelKey.self] ?? defaultModel
        currentModel = model
        var messages = turnHistory
        if let systemPrompt, !systemPrompt.isEmpty {
            messages = [OpenAIMessage.system(systemPrompt)] + messages
        }
        return OpenAIRequest(
            model: model,
            messages: messages,
            tools: effectiveTools,
            stream: true,
            streamOptions: OpenAIRequest.StreamOptions(includeUsage: true),
            temperature: parameters.configuration.temperature,
            maxCompletionTokens: parameters.configuration.maxTokens,
        )
    }

    func finishReason(from stopReason: String) -> FinishReason {
        switch stopReason {
        case "length":
            .maxTokens
        case "stop":
            .endTurn
        case "cancelled":
            .cancelled
        default:
            .endTurn
        }
    }
}

#endif
