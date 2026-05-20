// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension Agent {
    /// Creates a new agent definition from a system prompt and a single inference provider.
    ///
    /// Use this for the common case where all phases share the same provider and you
    /// do not need per-phase behavior configuration. For full control over phases,
    /// use ``init(agentId:provider:behavior:toolDefinition:toolBehavior:owner:sessionState:traceRetentionPolicy:)``
    /// with an explicit ``AgentBehavior``.
    ///
    /// - Parameters:
    ///   - agentId: Stable identifier for this agent. Defaults to a generated UUID.
    ///   - provider: The inference provider to use for all sessions.
    ///   - systemPrompt: Base instructions that define the agent's role.
    ///   - inferenceConfiguration: Inference parameters applied to all agent phases.
    ///   - defaultAutomaticCompactionPolicy: Default automatic compaction policy for new sessions.
    ///   - toolDefinition: The tools the agent may invoke and the policy governing their execution.
    ///     Defaults to ``ToolDefinition/noTools``.
    ///   - toolBehavior: Default tool execution behavior: step budget, selection, and prompt guidance.
    ///   - owner: The default user for sessions created from this agent. Defaults to ``UserID/local``.
    ///   - sessionState: Whether built-in session-state tools should be exposed.
    ///   - traceRetentionPolicy: In-memory retention policy applied to new session traces.
    public init<Provider: InferenceProviding>(
        agentId: AgentID = .generate(),
        provider: Provider,
        systemPrompt: String,
        inferenceConfiguration: InferenceConfiguration = InferenceConfiguration(),
        defaultAutomaticCompactionPolicy: AutomaticCompactionPolicy = .disabled,
        toolDefinition: ToolDefinition = .noTools,
        toolBehavior: ToolBehavior = ToolBehavior(),
        owner: UserID = .local,
        sessionState: SessionStateMode = .disabled,
        traceRetentionPolicy: TraceRetentionPolicy = .maxTurns(150),
    ) {
        self.init(
            agentId: agentId,
            provider: provider,
            behavior: AgentBehavior(
                systemPrompt: systemPrompt,
                inferenceConfiguration: inferenceConfiguration,
                defaultAutomaticCompactionPolicy: defaultAutomaticCompactionPolicy,
            ),
            toolDefinition: toolDefinition,
            toolBehavior: toolBehavior,
            owner: owner,
            sessionState: sessionState,
            traceRetentionPolicy: traceRetentionPolicy,
        )
    }
}
