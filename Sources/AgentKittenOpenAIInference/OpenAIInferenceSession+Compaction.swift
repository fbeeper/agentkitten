// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport

extension OpenAIInferenceSession: ContextCompactableSession {
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
            return .skipped(.failed("No OpenAI message history to compact."))
        }
        let usageBefore = uncheckedContextUsage()
        let plan = OpenAIMessageCompactionPlan(
            history: history,
            preservedRecentTurnCount: preservedRecentTurnCount,
        )
        if let summary {
            history = summaryMessages(summary) + plan.recentMessages
        } else {
            history = plan.recentMessages
        }
        cachedContextTokens = nil
        let usageAfter = uncheckedContextUsage()
        return .compacted(
            ContextCompactionResult.Compacted(
                usageBefore: usageBefore,
                usageAfter: usageAfter,
            ),
        )
    }
}

extension OpenAIInferenceSession {
    private static func isTurnStarter(_ message: OpenAIMessage) -> Bool {
        message.role == .user
    }

    func render(_ messages: [OpenAIMessage]) -> String {
        messages.map { render($0) }.joined(separator: "\n\n")
    }

    private func render(_ message: OpenAIMessage) -> String {
        let cfg = historyRenderingConfiguration
        switch message.role {
        case .system:
            return "\(cfg.userRoleLabel): \(contentText(of: message))"
        case .user:
            return "\(cfg.userRoleLabel): \(contentText(of: message))"
        case .assistant:
            var parts: [String] = []
            if let content = message.content, case .text(let text) = content, !text.isEmpty {
                parts.append(text)
            }
            if let toolCalls = message.toolCalls {
                parts += toolCalls.map { String(format: cfg.toolCallFormat, $0.function.name) }
            }
            return "\(cfg.assistantRoleLabel): \(parts.joined(separator: "\n"))"
        case .tool:
            let body = contentText(of: message)
            return String(format: cfg.toolResultFormat, body)
        }
    }

    private func contentText(of message: OpenAIMessage) -> String {
        switch message.content {
        case .text(let str):
            str
        case .parts(let parts):
            parts.compactMap { part -> String? in
                if case .text(let str) = part { return str } else { return nil }
            }.joined(separator: " ")
        case nil:
            ""
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
