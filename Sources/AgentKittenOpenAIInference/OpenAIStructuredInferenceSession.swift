// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import Foundation

extension OpenAIInferenceSession: StructuredInferenceSession {
    public func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws -> StructuredInferenceStream<T> {
        let lease = try operationGate.begin(.generate)
        do {
            let key = try await resolvedKey()
            let system = buildStructuredSystemPrompt(schemaJSON: encodeStructuredSchema(T.jsonSchema))
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
                            toolStepBudget: parameters.toolStepBudget,
                            context: parameters.toolExecutionContext,
                            toolSelection: parameters.toolSelection,
                        )
                        let client = clientFactory(key, baseURL)
                        var turnHistory = [OpenAIMessage.user(prompt)]
                        let outcome = try await runStructuredLoop(
                            client: client,
                            system: system,
                            parameters: parameters,
                            toolTurnRuntime: toolTurnRuntime,
                            turnHistory: &turnHistory,
                            continuation: continuation,
                        )
                        let value = try decodeStructuredValue(T.self, from: outcome.text)
                        continuation.yield(.result(value, finishReason(from: outcome.stopReason)))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    lease.end()
                    task.cancel()
                }
            }
        } catch {
            lease.end()
            throw error
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func runStructuredLoop<T: Sendable>(
        client: any OpenAIHTTPStreaming,
        system: String,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        continuation: StructuredInferenceStream<T>.Continuation,
    ) async throws -> (stopReason: String, text: String) {
        var stopReason = "stop"
        var accumulated = ""
        var toolUseResponsesSeen = 0
        repeat {
            let outcome = try await runStructuredRequest(
                client: client,
                system: system,
                parameters: parameters,
                toolTurnRuntime: toolTurnRuntime,
                turnHistory: &turnHistory,
                continuation: continuation,
            )
            stopReason = stopReasonAfterRequest(
                stopReason: outcome.stopReason,
                toolUseResponsesSeen: &toolUseResponsesSeen,
            )
            accumulated = outcome.text
        } while stopReason == "tool_calls"
        return (stopReason, accumulated)
    }

    // swiftlint:disable:next function_parameter_count
    private func runStructuredRequest<T: Sendable>(
        client: any OpenAIHTTPStreaming,
        system: String,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        continuation: StructuredInferenceStream<T>.Continuation,
    ) async throws -> (stopReason: String, text: String) {
        let selectedTools = tools.filter { parameters.toolSelection.allows(toolName: $0.function.name) }
        let effectiveTools: [OpenAITool]? = selectedTools.isEmpty ? nil : selectedTools
        let model = parameters.inferenceContext[OpenAIModelKey.self] ?? defaultModel
        var messages = turnHistory
        if !system.isEmpty {
            messages = [OpenAIMessage.system(system)] + messages
        }
        let request = OpenAIRequest(
            model: model,
            messages: messages,
            tools: effectiveTools,
            stream: true,
            streamOptions: nil,
            temperature: 0,
            maxTokens: 4096,
        )
        var textAccumulated = ""
        var pendingCalls: [PendingOpenAIToolCall] = []
        var stopReason = "stop"

        for try await event in client.stream(request: request) {
            try Task.checkCancellation()
            switch event {
            case .textDelta(let chunk):
                textAccumulated += chunk
            case .usage:
                // Structured generation uses a synthetic turn history that is not stored on
                // the session, so this token count does not correspond to self.history and
                // must not be cached via cachedContextTokens.
                break
            case .toolCallReady(let id, let name, let argsJSON):
                pendingCalls.append(PendingOpenAIToolCall(id: id, name: name, argsJSON: argsJSON))
            case .stopReason(let reason):
                stopReason = reason
            case .error(let message):
                throw InferenceError.invalidResponse(message)
            }
        }

        appendAssistantTurn(text: textAccumulated, toolCalls: pendingCalls, to: &turnHistory)
        try await executeStructuredToolCalls(
            pendingCalls,
            toolTurnRuntime: toolTurnRuntime,
            turnHistory: &turnHistory,
            continuation: continuation,
        )
        return (stopReason, textAccumulated)
    }

    private func executeStructuredToolCalls<T: Sendable>(
        _ calls: [PendingOpenAIToolCall],
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        continuation: StructuredInferenceStream<T>.Continuation,
    ) async throws {
        guard !calls.isEmpty else { return }
        for call in calls {
            let toolMessage = try await executeStructuredSingleTool(
                call,
                toolTurnRuntime: toolTurnRuntime,
                continuation: continuation,
            )
            turnHistory.append(toolMessage)
        }
    }

    private func executeStructuredSingleTool<T: Sendable>(
        _ call: PendingOpenAIToolCall,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: StructuredInferenceStream<T>.Continuation,
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

    private func decodeStructuredValue<T: Decodable>(
        _ type: T.Type,
        from json: String,
    ) throws(StructuredGenerationError) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw StructuredGenerationError.decodingFailed(error)
        }
    }

    private func encodeStructuredSchema(_ schema: JSONSchema) -> String {
        let value = OpenAIToolBridge.openAIJSONValue(from: schema)
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func buildStructuredSystemPrompt(schemaJSON: String) -> String {
        let instruction = String(format: structuredOutputInstructionFormat, schemaJSON)
        if let systemPrompt, !systemPrompt.isEmpty {
            return "\(systemPrompt)\n\n\(instruction)"
        }
        return instruction
    }
}
#endif
