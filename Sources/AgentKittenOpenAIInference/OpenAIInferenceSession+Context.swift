// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

extension OpenAIInferenceSession {
    /// Returns the token usage for the session's current history.
    ///
    /// OpenAI does not provide a separate token-counting endpoint. Usage is
    /// reported in the final stream chunk (`stream_options: {include_usage: true}`)
    /// and cached after each completed turn. Context size is resolved from a known
    /// model fallback or from compatible `/models/{model}` metadata when available.
    public func contextUsage() async throws -> ContextUsage {
        let lease = try operationGate.begin(.contextUsage)
        defer { lease.end() }
        let contextSize = await resolveContextSize(for: currentModel)
        return ContextUsage(contextTokens: cachedContextTokens ?? 0, contextSize: contextSize)
    }

    func resolveContextSize(for model: String) async -> Int? {
        if let cached = resolvedContextSizes[model] {
            return cached.value
        }

        let fallback = OpenAIModelContextWindow.standardMaxInputTokens(for: model)

        do {
            if let resolved = try await client.maxInputTokens(for: model), resolved > 0 {
                cacheResolvedContextSize(resolved, for: model)
                return resolved
            }
        } catch {
            cacheResolvedContextSize(fallback, for: model)
            return fallback
        }

        cacheResolvedContextSize(fallback, for: model)
        return fallback
    }

    func cacheResolvedContextSize(_ contextSize: Int?, for model: String) {
        if let contextSize {
            resolvedContextSizes[model] = .available(contextSize)
        } else {
            resolvedContextSizes[model] = .unavailable
        }
    }
}
#endif
