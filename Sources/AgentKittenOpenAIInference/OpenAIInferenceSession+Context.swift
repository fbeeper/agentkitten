// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

extension OpenAIInferenceSession {
    /// Returns the token usage for the session's current history.
    ///
    /// OpenAI does not provide a separate token-counting endpoint. Usage is
    /// reported in the final stream chunk (`stream_options: {include_usage: true}`)
    /// and cached after each completed turn. Returns zero with no context-size
    /// bound before the first turn.
    public func contextUsage() async throws -> ContextUsage {
        let lease = try operationGate.begin(.contextUsage)
        defer { lease.end() }
        return uncheckedContextUsage()
    }

    func uncheckedContextUsage() -> ContextUsage {
        ContextUsage(contextTokens: cachedContextTokens ?? 0, contextSize: nil)
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
            maxTokens: parameters.configuration.maxTokens,
        )
    }

    func stopReasonAfterRequest(
        stopReason: String,
        toolUseResponsesSeen: inout Int,
    ) -> String {
        guard stopReason == "tool_calls" else {
            return stopReason
        }
        toolUseResponsesSeen += 1
        if toolUseResponsesSeen > maxEmptyToolUseFollowUps {
            return "stop"
        }
        return "tool_calls"
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
