// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

struct AnthropicMessageCompactionPlan {
    let olderMessages: [AnthropicMessage]
    let recentMessages: [AnthropicMessage]

    init(history: [AnthropicMessage], preservedRecentTurnCount: Int) {
        let recentStart = Self.recentStartIndex(
            in: history,
            preservedRecentTurnCount: max(0, preservedRecentTurnCount),
        )
        olderMessages = Array(history[..<recentStart])
        recentMessages = Array(history[recentStart...])
    }

    private static func recentStartIndex(
        in history: [AnthropicMessage],
        preservedRecentTurnCount: Int,
    ) -> Int {
        guard preservedRecentTurnCount > 0 else {
            return history.endIndex
        }

        var userMessagesSeen = 0
        for index in history.indices.reversed() where history[index].role == .user {
            userMessagesSeen += 1
            if userMessagesSeen == preservedRecentTurnCount {
                return index
            }
        }
        return history.startIndex
    }
}
#endif
