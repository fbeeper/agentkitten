// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import Foundation

enum PlaygroundChatOutputFormatter {
    static let separator = "--------------------------------------------------"
    static let instructions = "Type a message and press Enter. Ctrl-D to exit."
    static let chatInstructions =
        "Type a message and press Enter. Use /usage, /clear, or /clear-keep-state. Ctrl-D to exit."

    static func sessionHeader(
        title: String,
        detailLines: [String],
        instructions: String = instructions,
    ) -> String {
        ([separator, title] + detailLines + [instructions, separator]).joined(separator: "\n")
    }

    static func userPrompt(userLabel: String = "You") -> String {
        [separator, "\(userLabel):"].joined(separator: "\n")
    }

    static func assistantHeader(assistantLabel: String) -> String {
        [separator, "\(assistantLabel):"].joined(separator: "\n")
    }

    static func turnError(_ error: any Error) -> String {
        let message = (error as? LocalizedError)?
            .errorDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let message, !message.isEmpty {
            return "[error: \(message)]"
        }

        return "[error: \(String(describing: error))]"
    }

    static func contextUsage(_ usage: ContextUsage?) -> String {
        guard let usage else {
            return "[usage: unavailable]"
        }

        guard let contextSize = usage.contextSize else {
            return "[usage: \(usage.contextTokens) tokens]"
        }

        let percent = Double(usage.contextTokens) / Double(contextSize) * 100
        let formattedPercent = percent.formatted(.number.precision(.fractionLength(0)))
        return "[usage: \(usage.contextTokens)/\(contextSize) tokens, \(formattedPercent)%]"
    }
}
