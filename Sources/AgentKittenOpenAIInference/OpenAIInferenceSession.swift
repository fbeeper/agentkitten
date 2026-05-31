// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation

/// A per-conversation session connected to an OpenAI Chat Completions API endpoint.
///
/// Manages wire-format conversation history (`[OpenAIMessage]`) and streams plain
/// text responses. Compatible with any OpenAI-spec endpoint including LM Studio.
/// The API key is fetched from ``APIKeyProviding`` at the start of each turn.
///
/// This text-only session does not yet support tool use, structured output,
/// token counting, or context compaction; those capabilities are layered on by
/// later extensions.
public actor OpenAIInferenceSession: InferenceSession {
    let client: any OpenAIHTTPStreaming
    let defaultModel: String
    let systemPrompt: String?
    let toolRuntime: ToolRuntime
    var currentModel: String
    var history: [OpenAIMessage]
    let operationGate = SingleFlightOperationGate<InferenceSessionOperationKind> {
        InferenceError.concurrentOperationInProgress(active: $0)
    }

    init(
        client: any OpenAIHTTPStreaming,
        defaultModel: String,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        initialHistory: [OpenAIMessage] = [],
    ) {
        self.client = client
        self.defaultModel = defaultModel
        self.systemPrompt = systemPrompt
        self.toolRuntime = toolRuntime
        history = initialHistory
        currentModel = defaultModel
    }

    /// Returns a snapshot of the current conversation history, captured under actor isolation.
    func captureHistory() -> [OpenAIMessage] {
        history
    }

    /// Runs a single inference turn and streams the model's text response.
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
        // Snapshot history + the new user message into a local buffer.
        // self.history is only updated on success; cancellation and errors
        // leave it unchanged so aborted turns are invisible to future sends.
        var turnHistory = history + [userMessage]
        do {
            let request = buildRequest(from: turnHistory, parameters: parameters)
            var textAccumulated = ""
            var stopReason = "stop"
            for try await event in try await client.stream(request: request) {
                try Task.checkCancellation()
                switch event {
                case .textDelta(let chunk):
                    continuation.yield(.delta(chunk))
                    textAccumulated += chunk
                case .stopReason(let reason):
                    stopReason = reason
                case .usage:
                    // Token usage is reported here, but contextUsage() is not yet
                    // supported by this text-only session, so ignore it for now.
                    break
                case .error(let message):
                    throw InferenceError.invalidResponse(message)
                }
            }
            turnHistory.append(OpenAIMessage.assistant(textAccumulated))
            history = turnHistory
            continuation.yield(.result(textAccumulated, finishReason(from: stopReason)))
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func buildRequest(
        from turnHistory: [OpenAIMessage],
        parameters: InferenceRequestParameters,
    ) -> OpenAIRequest {
        var messages = turnHistory
        if let systemPrompt, !systemPrompt.isEmpty {
            messages = [OpenAIMessage.system(systemPrompt)] + messages
        }
        return OpenAIRequest(
            model: currentModel,
            messages: messages,
            stream: true,
            streamOptions: OpenAIRequest.StreamOptions(includeUsage: true),
            temperature: parameters.configuration.temperature,
            maxTokens: parameters.configuration.maxTokens,
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

extension OpenAIInferenceSession: StructuredInferenceSession {
    /// Structured output is not supported by the text-only OpenAI session.
    ///
    /// Always throws ``InferenceError/unsupportedConfiguration(_:)``. A later
    /// extension adds schema-guided structured generation.
    public func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt _: String,
        parameters _: InferenceRequestParameters,
    ) async throws -> StructuredInferenceStream<T> {
        throw InferenceError.unsupportedConfiguration(
            "OpenAIInferenceSession does not yet support structured output.",
        )
    }
}
#endif
