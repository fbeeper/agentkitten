// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

/// Presents a plan to the user for interactive approval before any scratchpad edits.
struct ProposePlanTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let plan: String
    }

    struct Output: Codable, Sendable {
        let approved: Bool
        let message: String
    }

    static let name = "propose_plan"
    static let defaultDescription =
        "Submits a plan for user approval. The plan must include numbered steps " +
        "and key code snippets for each change. Call at most once per turn, " +
        "then make no further tool calls. Only available in plan mode."

    let state: PlanModeState

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "plan": .string(
                    description: "A concrete, step-by-step description of the changes to make.",
                ),
            ],
            required: ["plan"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        print("\n\n[plan proposed]")
        print(arguments.plan)
        print("\nApprove plan? [y]es / [n]o:", terminator: " ")
        flushStdout()

        guard let input = readLine() else {
            return Output(approved: false, message: "Plan rejected: no input received.")
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "y" || trimmed == "yes" {
            await state.recordApprovedPlan(arguments.plan)
            return Output(
                approved: true,
                message: "Plan approved. Do not make any further tool calls. End your response now.",
            )
        } else {
            await state.recordRejectedPlan()
            return Output(
                approved: false,
                message: "Plan rejected. Do not propose another plan. " +
                    "End your response and wait for the user's next message.",
            )
        }
    }
}
