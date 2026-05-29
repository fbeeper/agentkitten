// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation

extension OpenAIInferenceSession: StructuredInferenceSession {
    /// Generates a typed value by injecting `T`'s JSON schema into the system prompt
    /// and decoding the model's final text. Tool calls are allowed during generation.
    public func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws -> StructuredInferenceStream<T> {
        let lease = try operationGate.begin(.generate)
        let system = buildStructuredSystemPrompt(schemaJSON: encodeStructuredSchema(T.jsonSchema))
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let toolTurnRuntime = toolRuntime.makeTurnRuntime(
                        toolStepBudget: parameters.toolStepBudget,
                        context: parameters.toolExecutionContext,
                        toolSelection: parameters.toolSelection,
                    )
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
    }

    private struct LoopOutcome {
        let stopReason: String
        let text: String
    }

    // swiftlint:disable:next function_parameter_count
    private func runStructuredLoop<T: Sendable>(
        client: any OpenAIHTTPStreaming,
        system: String,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        continuation: StructuredInferenceStream<T>.Continuation,
    ) async throws -> LoopOutcome {
        var outcome = RequestOutcome(stopReason: "stop", text: "", hasToolCalls: false)
        var lastRoundText = ""
        repeat {
            try Task.checkCancellation()
            guard await toolTurnRuntime.prepareRound() else {
                break // Given the follow up stopReason is ok on tool_calls without having to set manually.
            }
            outcome = try await runStructuredRequest(
                client: client,
                system: system,
                parameters: parameters,
                toolTurnRuntime: toolTurnRuntime,
                turnHistory: &turnHistory,
                continuation: continuation,
            )
            lastRoundText = outcome.text
            await toolTurnRuntime.recordRound()
        } while outcome.hasToolCalls
        return LoopOutcome(stopReason: outcome.stopReason, text: lastRoundText)
    }

    private struct RequestOutcome {
        let stopReason: String
        let text: String
        let hasToolCalls: Bool
    }

    // swiftlint:disable:next function_parameter_count
    private func runStructuredRequest<T: Sendable>(
        client: any OpenAIHTTPStreaming,
        system: String,
        parameters: InferenceRequestParameters,
        toolTurnRuntime: ToolTurnRuntime,
        turnHistory: inout [OpenAIMessage],
        continuation: StructuredInferenceStream<T>.Continuation,
    ) async throws -> RequestOutcome {
        let selectedTools = tools.filter { parameters.toolSelection.allows(toolName: $0.function.name) }
        let effectiveTools: [OpenAITool]? = selectedTools.isEmpty ? nil : selectedTools
        var messages = turnHistory
        if !system.isEmpty {
            messages = [OpenAIMessage.system(system)] + messages
        }
        let request = OpenAIRequest(
            model: defaultModel,
            messages: messages,
            tools: effectiveTools,
            stream: true,
            streamOptions: nil,
            temperature: 0,
            maxCompletionTokens: 4096,
        )
        var textAccumulated = ""
        var pendingCalls: [PendingOpenAIToolCall] = []
        var stopReason = "stop"

        for try await event in try await client.stream(request: request) {
            try Task.checkCancellation()
            switch event {
            case .textDelta(let chunk):
                textAccumulated += chunk
            case .usage:
                // Structured generation uses a synthetic turn history that is not stored on
                // the session, so this token count must not be cached against self.history.
                break
            case .toolCallReady(let id, let name, let argsJSON):
                pendingCalls.append(PendingOpenAIToolCall(id: id, name: name, argsJSON: argsJSON))
            case .stopReason(let reason):
                stopReason = reason
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
