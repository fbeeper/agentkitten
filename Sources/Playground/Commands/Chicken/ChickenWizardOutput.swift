// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
import Foundation

enum ChickenWizardOutputFormatter {
    static let assistantLabel = "Chicken Wizard"
    static let introLines = [
        """
        Bawk. Welcome to the marsh tower. I am Bristlebeak, keeper of weather \
        talk, timekeeping, beastly gossip, and rare alchemy.
        """,
        "Ask about the skies, the hour, the beasts, or the contents of your satchel.",
    ]
    static let intro = introLines.joined(separator: "\n")
    static let goodbye = "Chicken Wizard: Bawk. Away with you."

    static func potionNotification(
        toolName: String,
        outcome: ToolCallOutcome,
    ) -> String? {
        guard toolName == ChickenWizardPotionTool.name else {
            return nil
        }
        guard case .success(let content) = outcome,
              let result = decodePotionOutput(from: content),
              result.brewed else {
            return nil
        }
        let consumed = result.consumedIngredients
            .map { "\($0.quantity)x \($0.name)" }
            .joined(separator: ", ")
        return "[ingredients consumed: \(consumed); potion brewed: \(result.potionName)]"
    }

    private static func decodePotionOutput(
        from content: [ToolResultContent],
    ) -> ChickenWizardPotionToolOutput? {
        guard case .text(let payload) = content.first,
              let data = payload.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ChickenWizardPotionToolOutput.self, from: data)
    }
}

enum ChickenWizardTurnStreamer {
    static func stream(_ turn: Turn<AssistantMessage>) async throws {
        var printedText = false
        var notifications: [String] = []

        for try await event in turn.events {
            switch event.kind {
            case .textDelta(let chunk):
                printedText = true
                print(chunk, terminator: "")
                fflush(stdout)
            case .result:
                if printedText {
                    print()
                    printedText = false
                }
                flushNotifications(&notifications)
            case .toolCallCompleted(let name, _, let outcome):
                if let notification = ChickenWizardOutputFormatter.potionNotification(
                    toolName: name,
                    outcome: outcome,
                ) {
                    notifications.append(notification)
                }
            case .toolCallStarted, .toolApprovalRequired:
                break
            }
        }

        if printedText {
            print()
        }
        flushNotifications(&notifications)
    }

    private static func flushNotifications(_ notifications: inout [String]) {
        for notification in notifications {
            print(notification)
        }
        notifications.removeAll(keepingCapacity: true)
    }
}
