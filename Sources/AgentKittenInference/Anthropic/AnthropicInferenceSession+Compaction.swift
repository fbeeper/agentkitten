// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

extension AnthropicInferenceSession: ContextCompactableSession {
    public func compactionEntries() -> [RenderedSessionEntry] {
        history.map {
            RenderedSessionEntry(isTurnStart: Self.isTurnStarter($0), rendered: Self.render($0))
        }
    }

    public func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int
    ) async throws -> ContextCompactionResult {
        guard !history.isEmpty else {
            return .skipped(.failed("No Anthropic message history to compact."))
        }
        let usageBefore = try await uncheckedContextUsage()
        let plan = AnthropicMessageCompactionPlan(
            history: history,
            preservedRecentTurnCount: preservedRecentTurnCount
        )
        if let summary {
            history = Self.summaryMessages(summary) + plan.recentMessages
        } else {
            history = plan.recentMessages
        }
        cachedContextTokens = nil
        let usageAfter = (try? await uncheckedContextUsage()) ?? usageBefore
        return .compacted(.init(usageBefore: usageBefore, usageAfter: usageAfter))
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

    static func render(_ messages: [AnthropicMessage]) -> String {
        messages.map { render($0) }.joined(separator: "\n\n")
    }

    private static func render(_ message: AnthropicMessage) -> String {
        let roleKey = message.role == .user
            ? "contextCompaction.userRoleLabel"
            : "contextCompaction.assistantRoleLabel"
        let role = AgentKittenInferenceLocalization.string(roleKey)
        let text = message.content.map { content -> String in
            switch content {
            case .text(let value):
                return value
            case .toolUse(_, let name, _):
                return AgentKittenInferenceLocalization.formattedString("contextCompaction.toolCallFormat", name)
            case .toolResult(_, let content, let isError):
                let body = content.compactMap { item -> String? in
                    if case .text(let text) = item {
                        return text
                    }
                    return nil
                }.joined(separator: " ")
                let formatKey = isError
                    ? "contextCompaction.toolErrorFormat"
                    : "contextCompaction.toolResultFormat"
                return AgentKittenInferenceLocalization.formattedString(formatKey, body)
            }
        }.joined(separator: "\n")
        return "\(role): \(text)"
    }

    private static func summaryMessages(_ summary: String) -> [AnthropicMessage] {
        [
            AnthropicMessage(
                role: .user,
                content: [.text(AgentKittenInferenceLocalization.string("contextCompaction.summaryMarker"))]
            ),
            AnthropicMessage(role: .assistant, content: [.text(summary)]),
        ]
    }
}
