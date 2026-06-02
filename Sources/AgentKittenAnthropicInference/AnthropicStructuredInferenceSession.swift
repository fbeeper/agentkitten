// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation

extension AnthropicInferenceSession: StructuredInferenceSession {
    public func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws
        -> StructuredInferenceStream<T> {
        let lease = try operationGate.begin(.generate)
        do {
            let key = try await apiKey()
            let system = buildStructuredSystemPrompt(schemaJSON: encodeStructuredSchema(T.jsonSchema))
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
                            toolStepBudget: parameters.toolStepBudget,
                            context: parameters.toolExecutionContext,
                            toolSelection: parameters.toolSelection,
                        )
                        let client = clientFactory(key)
                        var turnHistory = [AnthropicMessage(role: .user, content: [.text(prompt)])]
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

    private struct LoopOutcome {
        let stopReason: String
        let text: String
    }

    // swiftlint:disable:next function_parameter_count
    private func runStructuredLoop<T: Sendable>(
        client: any AnthropicHTTPStreaming,
        system: String,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [AnthropicMessage],
        continuation: StructuredInferenceStream<T>.Continuation,
    ) async throws -> LoopOutcome {
        var stopReason = "end_turn"
        var lastRoundText = ""
        var toolUseResponsesSeen = 0 // Tracks consecutive empty tool call cycles. Orthogonal to per-call budget.
        repeat {
            guard await toolTurnRuntime.prepareRound() else {
                break // Given the follow up stopReason is ok on tool_use without having to set manually.
            }
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
                hasToolCalls: outcome.hasToolCalls,
                toolUseResponsesSeen: &toolUseResponsesSeen,
            )
            lastRoundText = outcome.text
            await toolTurnRuntime.recordRound()
        } while stopReason == "tool_use"
        return LoopOutcome(stopReason: stopReason, text: lastRoundText)
    }

    private struct RequestOutcome {
        let stopReason: String
        let text: String
        let hasToolCalls: Bool
    }

    // swiftlint:disable:next function_parameter_count
    private func runStructuredRequest<T: Sendable>(
        client: any AnthropicHTTPStreaming,
        system: String,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [AnthropicMessage],
        continuation: StructuredInferenceStream<T>.Continuation,
    ) async throws -> RequestOutcome {
        let effectiveTools: [AnthropicTool]?
        let selectedTools = tools.filter {
            parameters.toolSelection.allows(toolName: $0.name)
        }
        effectiveTools = selectedTools.isEmpty ? nil : selectedTools
        let model = parameters.inferenceContext[AnthropicModelKey.self] ?? defaultModel
        let request = AnthropicRequest(
            model: model,
            maxTokens: 4096,
            system: system,
            messages: turnHistory,
            tools: effectiveTools,
            stream: true,
            temperature: 0,
        )
        var textAccumulated = ""
        var pendingCalls: [PendingSSEToolCall] = []
        var stopReason = "end_turn"

        for try await event in client.stream(request: request) {
            try Task.checkCancellation()
            switch event {
            case .textDelta(let chunk):
                textAccumulated += chunk
            case .usage:
                // Structured generation uses a synthetic turn history that is not stored on the
                // session, so this token count does not correspond to self.history and must not
                // be cached via cachedContextTokens.
                break
            case .toolCallReady(let id, let name, let argsJSON):
                pendingCalls.append(PendingSSEToolCall(id: id, name: name, argsJSON: argsJSON))
            case .stopReason(let reason):
                stopReason = reason
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
        return RequestOutcome(stopReason: stopReason, text: textAccumulated, hasToolCalls: !callsToExecute.isEmpty)
    }

    private func decodeStructuredValue<T: Decodable>(
        _ type: T.Type,
        from json: String,
    ) throws(StructuredGenerationError) -> T {
        try AgentKittenInferenceSupport.decodeStructuredValue(type, from: json)
    }

    private func encodeStructuredSchema(_ schema: JSONSchema) -> String {
        AgentKittenInferenceSupport.encodeStructuredSchema(schema)
    }

    private func buildStructuredSystemPrompt(schemaJSON: String) -> String {
        AgentKittenInferenceSupport.buildStructuredSystemPrompt(
            schemaJSON: schemaJSON,
            systemPrompt: systemPrompt,
            format: structuredOutputInstructionFormat,
        )
    }
}
#endif
