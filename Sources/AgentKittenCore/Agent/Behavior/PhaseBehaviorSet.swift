// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A set of per-phase behaviors with a shared fallback.
public struct PhaseBehaviorSet: Sendable {
    /// Default phase behavior used when a phase has no phase-specific behavior.
    public var base: PhaseBehavior
    private var behaviors: [AgentPhase: PhaseBehavior] = [:]

    /// Creates a phase-behavior set.
    ///
    /// - Parameter base: Default behavior used for phases without phase-specific behaviors.
    public init(base: PhaseBehavior = PhaseBehavior()) {
        self.base = base
    }

    /// Sets behavior for a specific phase.
    public mutating func set(_ behavior: PhaseBehavior, for phase: AgentPhase) {
        behaviors[phase] = behavior
    }

    /// Returns the effective behavior for `phase`.
    public func behavior(for phase: AgentPhase) -> PhaseBehavior {
        behaviors[phase] ?? base
    }
}
