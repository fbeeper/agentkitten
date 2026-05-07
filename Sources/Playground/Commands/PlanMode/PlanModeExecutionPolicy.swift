// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

/// Fail-safe execution policy: auto-approves tools called in the correct mode,
/// denies tools called in the wrong mode even if tool selection somehow allowed it.
struct PlanModeExecutionPolicy: ToolExecutionPolicy {
    let state: PlanModeState

    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        let mode = await state.mode
        let alreadyProposed = await state.planProposedThisTurn
        switch (call.name, mode) {
        case ("write_scratchpad", .plan):
            return .deny(
                reason: "write_scratchpad is not available in plan mode. " +
                    "Call propose_plan with your plan first."
            )
        case ("propose_plan", .code):
            return .deny(reason: "propose_plan is not available in code mode.")
        case ("propose_plan", _) where alreadyProposed:
            return .deny(reason: "propose_plan was already called this turn. " +
                "End your response and wait for the user's next message.")
        default:
            return .execute
        }
    }
}
