// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import AgentKittenCore
import Testing
@testable import Playground

@Suite("Playground Chat Output Formatter")
struct PlaygroundChatOutputFormatterTests {
    @Test func sessionHeader_includesSeparatorsAndInstructions() {
        let header = PlaygroundChatOutputFormatter.sessionHeader(
            title: "Chat",
            detailLines: [
                "AgentKitten Playground v1.0.0",
                "System: You are helpful.",
            ]
        )

        #expect(header == """
        --------------------------------------------------
        Chat
        AgentKitten Playground v1.0.0
        System: You are helpful.
        Type a message and press Enter. Ctrl-D to exit.
        --------------------------------------------------
        """)
    }

    @Test func chatInstructions_mentionsClearCommands() {
        #expect(PlaygroundChatOutputFormatter.chatInstructions.contains("/usage"))
        #expect(PlaygroundChatOutputFormatter.chatInstructions.contains("/clear"))
        #expect(PlaygroundChatOutputFormatter.chatInstructions.contains("/clear-keep-state"))
    }

    @Test func userPrompt_includesSharedSeparatorAndAttribution() {
        let prompt = PlaygroundChatOutputFormatter.userPrompt()

        #expect(prompt == """
        --------------------------------------------------
        You:
        """)
    }

    @Test func assistantHeader_includesSharedSeparatorAndAttribution() {
        let header = PlaygroundChatOutputFormatter.assistantHeader(assistantLabel: "Assistant")

        #expect(header == """
        --------------------------------------------------
        Assistant:
        """)
    }

    @Test func chickenUsesSharedAssistantLabel() {
        let header = PlaygroundChatOutputFormatter.assistantHeader(
            assistantLabel: ChickenWizardOutputFormatter.assistantLabel
        )

        #expect(header.contains(PlaygroundChatOutputFormatter.separator))
        #expect(header.contains("Chicken Wizard:"))
    }

    @Test func turnError_usesLocalizedDescriptionWhenAvailable() {
        let message = PlaygroundChatOutputFormatter.turnError(
            PlaygroundFormatterTestError.localized("Validation failed.")
        )

        #expect(message == "[error: Validation failed.]")
    }

    @Test func turnError_fallsBackToDebugDescription() {
        let message = PlaygroundChatOutputFormatter.turnError(
            PlaygroundFormatterTestError.plain
        )

        #expect(message.contains("[error:"))
        #expect(message.contains("plain"))
    }

    @Test func contextUsage_formatsKnownContextWindow() {
        let message = PlaygroundChatOutputFormatter.contextUsage(
            ContextUsage(contextTokens: 25, contextSize: 100)
        )

        #expect(message == "[usage: 25/100 tokens, 25%]")
    }

    @Test func contextUsage_formatsUnknownContextWindow() {
        let message = PlaygroundChatOutputFormatter.contextUsage(
            ContextUsage(contextTokens: 25)
        )

        #expect(message == "[usage: 25 tokens]")
    }

    @Test func contextUsage_formatsMissingUsage() {
        #expect(PlaygroundChatOutputFormatter.contextUsage(nil) == "[usage: unavailable]")
    }
}

private enum PlaygroundFormatterTestError: Error, LocalizedError {
    case plain
    case localized(String)

    var errorDescription: String? {
        switch self {
        case .plain:
            return nil
        case .localized(let message):
            return message
        }
    }
}
