// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension AgentBehavior {
    /// Creates behavior configuration applying a single inference configuration to all phases.
    ///
    /// Use this when you need to customize inference parameters but do not require
    /// per-phase overrides. For phase-specific configuration, use
    /// ``init(systemPrompt:phaseBehaviors:defaultAutomaticCompactionPolicy:)`` directly.
    ///
    /// - Parameters:
    ///   - systemPrompt: Base instructions that define the agent's role.
    ///   - inferenceConfiguration: Inference parameters applied to all agent phases.
    ///   - defaultAutomaticCompactionPolicy: Default automatic compaction policy for new sessions.
    public init(
        systemPrompt: String,
        inferenceConfiguration: InferenceConfiguration,
        defaultAutomaticCompactionPolicy: AutomaticCompactionPolicy = .disabled,
    ) {
        self.init(
            systemPrompt: systemPrompt,
            phaseBehaviors: PhaseBehaviorSet(base: PhaseBehavior(inferenceConfiguration: inferenceConfiguration)),
            defaultAutomaticCompactionPolicy: defaultAutomaticCompactionPolicy,
        )
    }

}
