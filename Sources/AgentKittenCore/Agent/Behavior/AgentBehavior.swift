// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Higher-order runtime behavior configuration for an ``Agent``.
///
/// Carries inference defaults and session-lifecycle policy. Tool-specific
/// defaults — step budget, selection, and prompt guidance — live in
/// ``ToolBehavior``.
public struct AgentBehavior: Sendable {
    /// Base instructions that define the agent's role.
    public let systemPrompt: String
    /// Default and per-phase behavior configuration.
    public let phaseBehaviors: PhaseBehaviorSet
    /// Default automatic compaction policy for new sessions.
    ///
    /// Each ``AgentSession`` receives a copy of this policy when it is created.
    /// Call ``AgentSession/setAutomaticCompactionPolicy(_:)`` to change the
    /// policy for one live session without changing the agent default.
    public let defaultAutomaticCompactionPolicy: AutomaticCompactionPolicy
    /// Creates behavior configuration for a new ``Agent``.
    ///
    /// - Parameter systemPrompt: Base instructions that define the agent's role.
    /// - Parameter phaseBehaviors: Default and per-phase behavior configuration.
    /// - Parameter defaultAutomaticCompactionPolicy: Default automatic compaction policy for new sessions.
    public init(
        systemPrompt: String,
        phaseBehaviors: PhaseBehaviorSet = .init(),
        defaultAutomaticCompactionPolicy: AutomaticCompactionPolicy = .disabled
    ) {
        self.systemPrompt = systemPrompt
        self.phaseBehaviors = phaseBehaviors
        self.defaultAutomaticCompactionPolicy = defaultAutomaticCompactionPolicy
    }

}
