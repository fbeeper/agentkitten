// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
import Foundation
@testable import Playground
import Testing

@Suite("Chicken Wizard")
struct ChickenWizardTests {
    @Test func gameState_startsBrewableAndConsumesIngredientsOnBrew() async {
        let state = ChickenWizardGameState()

        let initial = await state.inspectPantry()
        #expect(initial.brewable)
        #expect(!initial.brewed)
        #expect(initial.missingIngredients.isEmpty)

        let brewed = await state.brewPotion()
        #expect(brewed.brewed)
        #expect(brewed.brewable)
        #expect(brewed.consumedIngredients == [
            ChickenWizardIngredientStack(name: "moonmint", quantity: 1),
            ChickenWizardIngredientStack(name: "rainwater", quantity: 1),
            ChickenWizardIngredientStack(name: "sunseed", quantity: 1),
        ])
        #expect(
            brewed.availableIngredients.contains(
                ChickenWizardIngredientStack(
                    name: ChickenWizardGameState.potionInventoryKey,
                    quantity: 1,
                ),
            ),
        )

        let after = await state.inspectPantry()
        #expect(!after.brewable)
        #expect(
            after.availableIngredients.contains(
                ChickenWizardIngredientStack(
                    name: ChickenWizardGameState.potionInventoryKey,
                    quantity: 1,
                ),
            ),
        )
        #expect(after.missingIngredients == [
            ChickenWizardIngredientStack(name: "moonmint", quantity: 1),
            ChickenWizardIngredientStack(name: "rainwater", quantity: 1),
            ChickenWizardIngredientStack(name: "sunseed", quantity: 1),
        ])
    }

    @Test func brewGuard_requiresDirectPoliteRequest() async throws {
        let state = ChickenWizardGameState()
        let brewGuard = ChickenWizardBrewGuard()
        let tool = ChickenWizardPotionTool(gameState: state, brewGuard: brewGuard)

        await brewGuard.beginTurn(userMessage: "What ingredients are needed?")
        let blocked = try await tool.execute(arguments: .init(action: .brew))
        #expect(!blocked.brewed)
        #expect(blocked.message.contains("direct and polite request"))

        let pantryAfterBlockedAttempt = await state.inspectPantry()
        #expect(pantryAfterBlockedAttempt.brewable)

        await brewGuard.beginTurn(userMessage: "Please brew the potion for me.")
        let brewed = try await tool.execute(arguments: .init(action: .brew))
        #expect(brewed.brewed)
        #expect(
            brewed.availableIngredients.contains(
                ChickenWizardIngredientStack(
                    name: ChickenWizardGameState.potionInventoryKey,
                    quantity: 1,
                ),
            ),
        )
    }

    @Test func outputFormatter_onlyAnnouncesSuccessfulPotionBrews() throws {
        let brewOutput = ChickenWizardPotionToolOutput(
            action: "brew",
            potionName: ChickenWizardGameState.potionName,
            availableIngredients: [],
            requiredIngredients: [],
            missingIngredients: [],
            consumedIngredients: [
                ChickenWizardIngredientStack(name: "moonmint", quantity: 1),
                ChickenWizardIngredientStack(name: "rainwater", quantity: 1),
            ],
            brewable: true,
            brewed: true,
            message: "Brewed.",
        )
        let encoded = try JSONEncoder().encode(brewOutput)
        let outcome = ToolCallOutcome.success(content: [
            .text(try #require(String(data: encoded, encoding: .utf8))),
        ])

        let notification = ChickenWizardOutputFormatter.potionNotification(
            toolName: ChickenWizardPotionTool.name,
            outcome: outcome,
        )
        #expect(
            notification ==
                "[ingredients consumed: 1x moonmint, 1x rainwater; " +
                "potion brewed: Elixir of Astonishing Second Chances]",
        )

        #expect(
            ChickenWizardOutputFormatter.potionNotification(
                toolName: CurrentTimeTool.name,
                outcome: outcome,
            ) == nil,
        )
    }

    @Test func intro_mentionsStartingGuidance() {
        #expect(ChickenWizardOutputFormatter.intro.contains("Bristlebeak"))
        #expect(ChickenWizardOutputFormatter.intro.contains("rare alchemy"))
        #expect(ChickenWizardOutputFormatter.intro.contains("satchel"))
    }

    @Test func turnPolicy_allowsOnlyPoliteBrewRequests() {
        #expect(!ChickenWizardTurnPolicy.allowsBrewing(for: "brew the potion"))
        #expect(!ChickenWizardTurnPolicy.allowsBrewing(for: "What ingredients are needed?"))
        #expect(ChickenWizardTurnPolicy.allowsBrewing(for: "Please brew the potion for me."))
        #expect(ChickenWizardTurnPolicy.allowsBrewing(for: "Could you make the elixir, please?"))
    }
}
