// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
import AgentKittenInferenceSupport

extension AnthropicInferenceSession: ContextCompactableSession {
    public func compactionEntries() -> [RenderedSessionEntry] {
        history.map {
            RenderedSessionEntry(isTurnStart: Self.isTurnStarter($0), rendered: render($0))
        }
    }

    public func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int,
    ) async throws -> ContextCompactionResult {
        guard !history.isEmpty else {
            return .skipped(.failed("No Anthropic message history to compact."))
        }
        let usageBefore = try await uncheckedContextUsage()
        let plan = AnthropicMessageCompactionPlan(
            history: history,
            preservedRecentTurnCount: preservedRecentTurnCount,
        )
        if let summary {
            history = summaryMessages(summary) + plan.recentMessages
        } else {
            history = plan.recentMessages
        }
        cachedContextTokens = nil
        let usageAfter = (try? await uncheckedContextUsage()) ?? usageBefore
        return .compacted(
            ContextCompactionResult.Compacted(
                usageBefore: usageBefore,
                usageAfter: usageAfter,
            ),
        )
    }
}

extension AnthropicInferenceSession {
    private static func isTurnStarter(_ message: AnthropicMessage) -> Bool {
        guard message.role == .user else {
            return false
        }
        let isToolResult = message.content.contains {
            if case .toolResult = $0 { true } else { false }
        }
        return !isToolResult
    }

    func render(_ messages: [AnthropicMessage]) -> String {
        messages.map { render($0) }.joined(separator: "\n\n")
    }

    private func render(_ message: AnthropicMessage) -> String {
        let cfg = historyRenderingConfiguration
        let role = message.role == .user ? cfg.userRoleLabel : cfg.assistantRoleLabel
        let text = message.content.map { content -> String in
            switch content {
            case .text(let value):
                return value
            case .toolUse(_, let name, _):
                return String(format: cfg.toolCallFormat, name)
            case .toolResult(_, let content, let isError):
                let body = content.compactMap { item -> String? in
                    if case .text(let text) = item {
                        return text
                    }
                    return nil
                }.joined(separator: " ")
                let format = isError ? cfg.toolErrorFormat : cfg.toolResultFormat
                return String(format: format, body)
            }
        }.joined(separator: "\n")
        return "\(role): \(text)"
    }

    private func summaryMessages(_ summary: String) -> [AnthropicMessage] {
        [
            AnthropicMessage(
                role: .user,
                content: [.text(historyRenderingConfiguration.summaryMarker)],
            ),
            AnthropicMessage(role: .assistant, content: [.text(summary)]),
        ]
    }
}
