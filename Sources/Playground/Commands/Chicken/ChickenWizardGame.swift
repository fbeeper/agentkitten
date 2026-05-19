// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
import Foundation

enum ChickenWizardTurnPolicy {
    static func allowsBrewing(for userMessage: String) -> Bool {
        let text = userMessage.lowercased()
        let hasPolitenessMarker = [
            "please",
            "kindly",
            "would you",
            "could you",
            "can you",
            "may you",
        ].contains { text.contains($0) }
        guard hasPolitenessMarker else {
            return false
        }

        let explicitBrewIntent = [
            "brew",
            "concoct",
        ].contains { text.contains($0) }
        if explicitBrewIntent {
            return true
        }

        let potionMakingIntent = [
            "make",
            "mix",
            "craft",
            "prepare",
        ].contains { text.contains($0) }
        let potionTarget = [
            "potion",
            "elixir",
            "draught",
        ].contains { text.contains($0) }
        return potionMakingIntent && potionTarget
    }
}

actor ChickenWizardBrewGuard {
    private var brewingAllowed = false

    func beginTurn(userMessage: String) {
        brewingAllowed = ChickenWizardTurnPolicy.allowsBrewing(for: userMessage)
    }

    func allowsBrewing() -> Bool {
        brewingAllowed
    }
}

struct ChickenWizardIngredientStack: Codable, Sendable, Equatable {
    let name: String
    let quantity: Int
}

struct ChickenWizardPotionToolOutput: Codable, Sendable, Equatable {
    let action: String
    let potionName: String
    let availableIngredients: [ChickenWizardIngredientStack]
    let requiredIngredients: [ChickenWizardIngredientStack]
    let missingIngredients: [ChickenWizardIngredientStack]
    let consumedIngredients: [ChickenWizardIngredientStack]
    let brewable: Bool
    let brewed: Bool
    let message: String
}

actor ChickenWizardGameState {
    static let potionName = "Elixir of Astonishing Second Chances"
    static let potionInventoryKey = "elixir_of_astonishing_second_chances"

    static let recipe: [String: Int] = [
        "moonmint": 1,
        "rainwater": 1,
        "sunseed": 1,
    ]

    static let starterIngredients: [String: Int] = [
        "feather_of_self_doubt": 1,
        "moonmint": 1,
        "newt_tears": 2,
        "rainwater": 1,
        "sunseed": 1,
    ]

    private var inventory: [String: Int]

    init() {
        inventory = Self.starterIngredients
    }

    init(inventory: [String: Int]) {
        self.inventory = inventory
    }

    func inspectPantry() -> ChickenWizardPotionToolOutput {
        let missing = Self.missingIngredients(
            required: Self.recipe,
            available: inventory,
        )
        return ChickenWizardPotionToolOutput(
            action: ChickenWizardPotionTool.Action.inspect.rawValue,
            potionName: Self.potionName,
            availableIngredients: Self.stacks(from: inventory),
            requiredIngredients: Self.stacks(from: Self.recipe),
            missingIngredients: Self.stacks(from: missing),
            consumedIngredients: [],
            brewable: missing.isEmpty,
            brewed: false,
            message: missing.isEmpty
                ? "The potion can be brewed with the ingredients on hand."
                : "The pantry is missing ingredients for the potion.",
        )
    }

    func brewPotion() -> ChickenWizardPotionToolOutput {
        let missing = Self.missingIngredients(
            required: Self.recipe,
            available: inventory,
        )
        guard missing.isEmpty else {
            return ChickenWizardPotionToolOutput(
                action: ChickenWizardPotionTool.Action.brew.rawValue,
                potionName: Self.potionName,
                availableIngredients: Self.stacks(from: inventory),
                requiredIngredients: Self.stacks(from: Self.recipe),
                missingIngredients: Self.stacks(from: missing),
                consumedIngredients: [],
                brewable: false,
                brewed: false,
                message: "Brewing failed because required ingredients are missing.",
            )
        }

        for (name, quantity) in Self.recipe {
            inventory[name, default: 0] -= quantity
            if inventory[name] == 0 {
                inventory.removeValue(forKey: name)
            }
        }
        inventory[Self.potionInventoryKey, default: 0] += 1

        return ChickenWizardPotionToolOutput(
            action: ChickenWizardPotionTool.Action.brew.rawValue,
            potionName: Self.potionName,
            availableIngredients: Self.stacks(from: inventory),
            requiredIngredients: Self.stacks(from: Self.recipe),
            missingIngredients: [],
            consumedIngredients: Self.stacks(from: Self.recipe),
            brewable: true,
            brewed: true,
            message: "The chicken wizard brewed the potion and consumed the required ingredients.",
        )
    }

    private static func missingIngredients(
        required: [String: Int],
        available: [String: Int],
    ) -> [String: Int] {
        var missing: [String: Int] = [:]
        for (name, requiredQuantity) in required {
            let present = available[name, default: 0]
            if present < requiredQuantity {
                missing[name] = requiredQuantity - present
            }
        }
        return missing
    }

    private static func stacks(from ingredients: [String: Int]) -> [ChickenWizardIngredientStack] {
        ingredients
            .filter { $0.value > 0 }
            .map { ChickenWizardIngredientStack(name: $0.key, quantity: $0.value) }
            .sorted { lhs, rhs in
                lhs.name < rhs.name
            }
    }
}

struct ChickenWizardPotionTool: AgentTool {
    enum Action: String, Codable, Sendable {
        case inspect
        case brew
    }

    struct Arguments: Codable, Sendable {
        let action: Action
    }

    typealias Output = ChickenWizardPotionToolOutput

    static let name = "chicken_potion"
    static let defaultDescription =
        """
        Inspects the player's potion ingredients or brews the chicken wizard's \
        single life-altering potion, consuming ingredients on success. Brewing \
        should only be attempted after the user directly and politely asks for it.
        """

    let gameState: ChickenWizardGameState
    let brewGuard: ChickenWizardBrewGuard

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "action": .enumeration(
                    values: [
                        Action.inspect.rawValue,
                        Action.brew.rawValue,
                    ],
                    description: "Use inspect to check ingredients and brew to make the potion.",
                ),
            ],
            required: ["action"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        switch arguments.action {
        case .inspect:
            return await gameState.inspectPantry()
        case .brew:
            guard await brewGuard.allowsBrewing() else {
                let pantry = await gameState.inspectPantry()
                return ChickenWizardPotionToolOutput(
                    action: Action.brew.rawValue,
                    potionName: pantry.potionName,
                    availableIngredients: pantry.availableIngredients,
                    requiredIngredients: pantry.requiredIngredients,
                    missingIngredients: pantry.missingIngredients,
                    consumedIngredients: [],
                    brewable: pantry.brewable,
                    brewed: false,
                    message: "Brewing requires a direct and polite request in the current turn.",
                )
            }
            return await gameState.brewPotion()
        }
    }
}
