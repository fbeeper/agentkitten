// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

extension OpenAIInferenceSession: ContextCompactableSession {
    /// Renders the stored history as labelled entries for the context compactor.
    public func compactionEntries() -> [RenderedSessionEntry] {
        history.map {
            RenderedSessionEntry(isTurnStart: $0.role == .user, rendered: render($0))
        }
    }

    /// Replaces older history with an optional summary, keeping the most recent turns.
    public func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int,
    ) async throws -> ContextCompactionResult {
        guard !history.isEmpty else {
            return .skipped(.failed("No OpenAI message history to compact."))
        }
        let contextSize = try await resolveContextSize(for: currentModel)
        let usageBefore = try await uncheckedContextUsage(contextSize: contextSize)
        let plan = TurnPreservationPlan(
            entries: history,
            preservedRecentTurnCount: preservedRecentTurnCount,
            isTurnStart: { $0.role == .user },
        )
        if let summary {
            history = summaryMessages(summary) + plan.recentEntries(from: history)
        } else {
            history = plan.recentEntries(from: history)
        }
        // Invalidate the cached count so the next call re-probes with the compacted history.
        cachedContextTokens = .unknown
        let usageAfter = (try? await uncheckedContextUsage(contextSize: contextSize))
            ?? ContextUsage(contextTokens: .unknown, contextSize: TokenCount(contextSize))
        return .compacted(
            ContextCompactionResult.Compacted(
                usageBefore: usageBefore,
                usageAfter: usageAfter,
            ),
        )
    }
}

extension OpenAIInferenceSession {
    private func render(_ message: OpenAIMessage) -> String {
        let cfg = historyRenderingConfiguration
        let body = message.content ?? ""
        switch message.role {
        case .system:
            return "\(cfg.systemRoleLabel): \(body)"
        case .user:
            return "\(cfg.userRoleLabel): \(body)"
        case .assistant:
            var parts: [String] = []
            if !body.isEmpty {
                parts.append(body)
            }
            if let toolCalls = message.toolCalls {
                parts += toolCalls.map { String(format: cfg.toolCallFormat, $0.function.name) }
            }
            return "\(cfg.assistantRoleLabel): \(parts.joined(separator: "\n"))"
        case .tool:
            return String(format: cfg.toolResultFormat, body)
        }
    }

    private func summaryMessages(_ summary: String) -> [OpenAIMessage] {
        [
            OpenAIMessage.user(historyRenderingConfiguration.summaryMarker),
            OpenAIMessage.assistant(text: summary, toolCalls: nil),
        ]
    }
}
#endif
