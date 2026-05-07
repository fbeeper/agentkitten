// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Tracks the current plan/code mode and any pending approved plan.
actor PlanModeState {
    enum Mode {
        case plan
        case code
    }

    private(set) var mode: Mode = .plan
    private(set) var planProposedThisTurn: Bool = false
    private var pendingApprovedPlan: String?

    /// Resets per-turn state at the start of each new user turn.
    func beginTurn() {
        planProposedThisTurn = false
    }

    /// Switches to the given mode.
    func switchTo(_ newMode: Mode) {
        mode = newMode
    }

    /// Records a user-approved plan and switches to code mode.
    func recordApprovedPlan(_ plan: String) {
        planProposedThisTurn = true
        pendingApprovedPlan = plan
        mode = .code
    }

    /// Records that a plan was proposed and rejected this turn.
    func recordRejectedPlan() {
        planProposedThisTurn = true
    }

    /// Returns the pending approved plan and clears it, or `nil` if none.
    func consumeApprovedPlan() -> String? {
        defer { pendingApprovedPlan = nil }
        return pendingApprovedPlan
    }
}
