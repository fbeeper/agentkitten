// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

extension OpenAIInferenceSession {
    /// Returns the token usage for the session's current history.
    ///
    /// OpenAI does not provide a dedicated token-counting endpoint. Usage is
    /// reported in the final stream chunk (`stream_options: {include_usage: true}`)
    /// and cached after each completed turn. When the cache is empty (e.g. after
    /// context compaction), a minimal probe request with `max_completion_tokens: 1`
    /// is sent to obtain an accurate count without affecting history.
    /// Context size is resolved from a known model fallback or from compatible
    /// `/models/{model}` metadata when available.
    public func contextUsage() async throws -> ContextUsage {
        let lease = try operationGate.begin(.contextUsage)
        defer { lease.end() }
        return try await uncheckedContextUsage()
    }

    /// Computes context usage without acquiring an operation lease.
    ///
    /// Callers that already hold the conversation operation gate (e.g. context
    /// compaction) use this to avoid a self-deadlock on the single-flight gate.
    func uncheckedContextUsage() async throws -> ContextUsage {
        let contextSize = try await resolveContextSize(for: currentModel)
        return try await uncheckedContextUsage(contextSize: contextSize)
    }

    func uncheckedContextUsage(contextSize: Int?) async throws -> ContextUsage {
        let size = TokenCount(contextSize)
        if history.isEmpty {
            return ContextUsage(contextTokens: 0, contextSize: size)
        }
        if cachedContextTokens != .unknown {
            return ContextUsage(contextTokens: cachedContextTokens, contextSize: size)
        }
        try await countTokens()
        return ContextUsage(contextTokens: cachedContextTokens, contextSize: size)
    }

    /// Count tokens in history.
    ///
    /// - IMPORTANT:This is a significant workaround with API usage/cost implications.
    ///   OpenAI has no dedicated count-tokens endpoint for the chat completions api.
    ///   So, this fires a streaming Chat Completions call with `max_completion_tokens: 1`
    ///   and reads only the `usage` event, leaving the session `history` untouched.
    private func countTokens() async throws {
        var messages = history
        if let systemPrompt, !systemPrompt.isEmpty {
            messages = [OpenAIMessage.system(systemPrompt)] + messages
        }
        let request = OpenAIRequest(
            model: currentModel,
            messages: messages,
            tools: tools.isEmpty ? nil : tools,
            stream: true,
            streamOptions: OpenAIRequest.StreamOptions(includeUsage: true),
            temperature: 1.0,
            maxCompletionTokens: 1,
        )
        for try await event in try await client.stream(request: request) {
            if case .usage(let total) = event {
                cachedContextTokens = TokenCount(total)
                return
            }
        }
        throw InferenceError.invalidResponse("No usage event in token-count probe response.")
    }

    func resolveContextSize(for model: String) async throws -> Int? {
        // An explicit override (OpenAIContextWindowKey) wins over endpoint discovery:
        // it is the deterministic escape hatch for servers that do not report a window.
        if let currentContextWindowOverride {
            return currentContextWindowOverride
        }
        if let cached = resolvedContextSizes[model] {
            return cached
        }

        do {
            if let resolved = try await client.maxInputTokens(for: model), resolved > 0 {
                resolvedContextSizes[model] = resolved
                return resolved
            }
        } catch InferenceError.authenticationFailed(let info) {
            throw InferenceError.authenticationFailed(info)
        } catch {
            return nil
        }

        return nil
    }
}
#endif
