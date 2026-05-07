// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import ArgumentParser
import Darwin
import AgentKitten
import AgentKittenCore

extension Playground {
    /// Minimal role-playing chat with a reserved chicken wizard.
    struct Chicken: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Chat with a reserved chicken wizard."
        )

        @Option(name: .long, help: "Inference provider: apple or anthropic.")
        var provider: ProviderOption = .apple

        mutating func validate() throws {
            guard provider != .mock else {
                throw ValidationError("--provider mock is not supported for chicken chat.")
            }
        }

        func run() async throws {
            let gameState = ChickenWizardGameState()
            let brewGuard = ChickenWizardBrewGuard()
            let behavior = AgentBehavior(systemPrompt: Self.systemPrompt)
            let agent = Agent(
                providerRegistry: try PlaygroundProviderFactory.makeRegistry(for: provider),
                behavior: behavior,
                toolDefinition: ToolDefinition(
                    tools: [
                        AnyAgentTool(CurrentTimeTool()),
                        AnyAgentTool(ChickenWizardPotionTool(gameState: gameState, brewGuard: brewGuard)),
                    ],
                    executionPolicy: AnyToolExecutionPolicy(AutoApprovePolicy())
                )
            )
            try await chat(agent: agent, brewGuard: brewGuard)
        }

        private func chat(agent: Agent, brewGuard: ChickenWizardBrewGuard) async throws {
            print(
                PlaygroundChatOutputFormatter.sessionHeader(
                    title: "Chicken Wizard Chat",
                    detailLines: ChickenWizardOutputFormatter.introLines
                )
            )

            let session = agent.makeSession()
            while true {
                print()
                print(PlaygroundChatOutputFormatter.userPrompt())
                fflush(stdout)
                guard let line = readLine(), !line.isEmpty else {
                    break
                }
                await brewGuard.beginTurn(userMessage: line)
                let turn = try await session.send(line)
                print()
                print(
                    PlaygroundChatOutputFormatter.assistantHeader(
                        assistantLabel: ChickenWizardOutputFormatter.assistantLabel
                    )
                )
                fflush(stdout)
                try await ChickenWizardTurnStreamer.stream(turn)
                print(PlaygroundChatOutputFormatter.separator)
            }

            print()
            print(ChickenWizardOutputFormatter.goodbye)
        }

        private static let systemPrompt = """
        You are Bristlebeak, a reserved chicken wizard in a tiny role-playing game.
        Stay in character at all times.
        You may comfortably discuss weather, the current time, other animals, \
        the player's potion ingredients, your single life-altering potion, and \
        brief guidance about this small game world.
        For anything else, refuse briefly and in character. Do not become a \
        general-purpose assistant.
        Keep replies short and conversational.
        Use current_time for time questions.
        When potion matters arise, be proactive about checking the player's \
        ingredients with chicken_potion before deciding what is possible.
        If the user asks what ingredients are needed or what they currently have, \
        answer only with ingredient information and do not brew.
        Only use chicken_potion with action brew when the user clearly asks you \
        to make the potion and does so politely.
        If brewing succeeds, acknowledge that the ingredients were consumed and \
        the finished potion now belongs to the player as an inventory item.
        """
    }
}
