// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

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

    func resolveContextSize(for model: String) async -> Int? {
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
        hasToolCalls: Bool,
        toolUseResponsesSeen: inout Int, // Tracks consecutive empty tool call cycles. Orthogonal to per-call budget.
    ) -> String {
        guard stopReason == "tool_use" else {
            // The model finished normally (end_turn, max_tokens, etc.).
            // Reset counter to 0.
            // Loop expected to exit.
            toolUseResponsesSeen = 0
            return stopReason
        }
        guard !hasToolCalls else {
            // Legitimate tool round-trip.
            // Reset counter to 0, return "tool_use".
            // Loop expected to continue.
            toolUseResponsesSeen = 0
            return "tool_use"
        }

        // Anthropic can return repeated `tool_use` stop reasons without yielding any
        // executable tool calls. Increment this local counter.
        toolUseResponsesSeen += 1

        // We cap those follow-up cycles separately from per-call execution budgeting,
        // which is enforced in `executeToolCalls`.
        if toolUseResponsesSeen >= maxEmptyToolUseFollowUps {
            // Loop expected to exit.
            return "end_turn"
        } else {
            // Expected to retry otherwise.
            return "tool_use"
        }
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
#endif
