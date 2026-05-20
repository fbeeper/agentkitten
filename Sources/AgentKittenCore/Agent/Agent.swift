// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Immutable definition and default configuration for an AI agent.
///
/// `Agent` stores identity, behavior, tools, provider configuration, and the
/// default owner used when creating sessions. Runtime state such as queued
/// turns, conversations, and traces lives on ``AgentSession``.
public struct Agent: Sendable {
    /// The unique identifier for this agent definition.
    public let agentId: AgentID
    /// The default owner used by ``makeSession()``.
    public let owner: UserID

    private let behavior: AgentBehavior
    private let toolBehavior: ToolBehavior
    private let traceRetentionPolicy: TraceRetentionPolicy
    private let providerRegistry: ProviderRegistry
    private let toolDefinition: ToolDefinition
    private let sessionStateMode: SessionStateMode

    /// Creates a new agent definition.
    ///
    /// - Parameters:
    ///   - agentId: Stable identifier for this agent. Defaults to a generated UUID.
    ///   - providerRegistry: Available inference providers, including the default provider.
    ///   - behavior: Higher-order runtime behavior configuration.
    ///   - toolDefinition: The tools the agent may invoke and the policy governing their execution.
    ///     Defaults to ``ToolDefinition/noTools``.
    ///   - toolBehavior: Default tool execution behavior: step budget, selection, and prompt guidance.
    ///     Defaults to ``ToolBehavior/init()``.
    ///   - owner: The default user for sessions created from this agent. Defaults to ``UserID/local``.
    ///   - sessionState: Whether built-in session-state tools should be exposed.
    ///   - traceRetentionPolicy: In-memory retention policy applied to new session traces.
    public init(
        agentId: AgentID = .generate(),
        providerRegistry: ProviderRegistry,
        behavior: AgentBehavior,
        toolDefinition: ToolDefinition = .noTools,
        toolBehavior: ToolBehavior = ToolBehavior(),
        owner: UserID = .local,
        sessionState: SessionStateMode = .disabled,
        traceRetentionPolicy: TraceRetentionPolicy = .maxTurns(150),
    ) {
        switch sessionState {
        case .disabled:
            break
        case .readOnly, .enabled:
            // Reserve the full built-in state-tool surface for both modes.
            // Read-only sessions do not currently register the write tools, but
            // rejecting those names up front avoids mode-dependent collisions
            // and keeps room for future evolution without changing the naming
            // contract.
            let reservedNames = SessionStateBuiltins.reservedNames
            for tool in toolDefinition.registry.all {
                precondition(
                    !reservedNames.contains(tool.name),
                    "Tool name '\(tool.name)' is reserved by AgentKitten session-state tooling.",
                )
            }
        }
        self.init(
            agentId: agentId,
            owner: owner,
            behavior: behavior,
            toolBehavior: toolBehavior,
            providerRegistry: providerRegistry,
            toolDefinition: toolDefinition,
            sessionStateMode: sessionState,
            traceRetentionPolicy: traceRetentionPolicy,
        )
    }

    /// Creates a new agent definition using a single inference provider.
    ///
    /// A ``ProviderRegistry`` is created internally with `provider` as the default.
    /// Use this init for the common single-provider case to avoid registry boilerplate.
    ///
    /// - Parameters:
    ///   - agentId: Stable identifier for this agent. Defaults to a generated UUID.
    ///   - provider: The inference provider to use for all sessions.
    ///   - behavior: Higher-order runtime behavior configuration.
    ///   - toolDefinition: The tools the agent may invoke and the policy governing their execution.
    ///     Defaults to ``ToolDefinition/noTools``.
    ///   - toolBehavior: Default tool execution behavior: step budget, selection, and prompt guidance.
    ///     Defaults to ``ToolBehavior/init()``.
    ///   - owner: The default user for sessions created from this agent. Defaults to ``UserID/local``.
    ///   - sessionState: Whether built-in session-state tools should be exposed.
    ///   - traceRetentionPolicy: In-memory retention policy applied to new session traces.
    public init<Provider: InferenceProviding>(
        agentId: AgentID = .generate(),
        provider: Provider,
        behavior: AgentBehavior,
        toolDefinition: ToolDefinition = .noTools,
        toolBehavior: ToolBehavior = ToolBehavior(),
        owner: UserID = .local,
        sessionState: SessionStateMode = .disabled,
        traceRetentionPolicy: TraceRetentionPolicy = .maxTurns(150),
    ) {
        self.init(
            agentId: agentId,
            providerRegistry: ProviderRegistry(default: provider),
            behavior: behavior,
            toolDefinition: toolDefinition,
            toolBehavior: toolBehavior,
            owner: owner,
            sessionState: sessionState,
            traceRetentionPolicy: traceRetentionPolicy,
        )
    }

    /// Creates a fresh session using this agent's default owner.
    ///
    /// The session creates its approval coordinator internally. Interactive
    /// callers can resolve pending approvals through ``AgentSession/approve(callID:)``
    /// and ``AgentSession/deny(callID:reason:)``.
    ///
    /// - Returns: A caller-owned session with isolated runtime state.
    public func makeSession() -> AgentSession {
        makeSession(for: owner)
    }

    /// Creates a fresh queued session using this agent's default owner.
    ///
    /// This wrapper preserves FIFO serialization semantics on top of the
    /// direct single-flight ``AgentSession``.
    public func makeQueuedSession() -> AgentQueuedSession {
        makeQueuedSession(for: owner)
    }

    /// Creates a fresh session for the provided owner.
    ///
    /// The session creates its approval coordinator internally. Interactive
    /// callers can resolve pending approvals through ``AgentSession/approve(callID:)``
    /// and ``AgentSession/deny(callID:reason:)``.
    ///
    /// - Parameter owner: The owner to associate with the new session.
    /// - Returns: A caller-owned session with isolated runtime state.
    public func makeSession(for owner: UserID) -> AgentSession {
        let approvalGate = ToolApprovalGate()
        let trace = AgentTrace(retentionPolicy: traceRetentionPolicy)
        let stateAccess = switch sessionStateMode {
        case .disabled:
            AgentSession.SessionStateAccess.disabled
        case .readOnly:
            AgentSession.SessionStateAccess.readOnly(SessionState(
                trace: trace,
                access: .readOnly,
            ))
        case .enabled:
            AgentSession.SessionStateAccess.enabled(SessionState(trace: trace))
        }
        let sessionToolDefinition = makeSessionToolDefinition(
            stateAccess: stateAccess,
        )
        let conversationFactory = ConversationAssembler(
            phaseBehaviors: behavior.phaseBehaviors,
            providerRegistry: providerRegistry,
            baseSystemPrompt: makeSessionSystemPrompt(registry: sessionToolDefinition.registry),
            toolDefinition: sessionToolDefinition,
            runtimeConfig: toolBehavior.runtimeConfig,
            toolApprovalGate: approvalGate,
        )
        return AgentSession(
            sessionID: .generate(),
            agentID: agentId,
            ownerID: owner,
            trace: trace,
            state: stateAccess,
            approvalGate: approvalGate,
            behavior: behavior,
            toolBehavior: toolBehavior,
            conversationFactory: conversationFactory,
        )
    }

    /// Creates a fresh queued session for the provided owner.
    ///
    /// This wrapper preserves FIFO serialization semantics on top of the
    /// direct single-flight ``AgentSession``.
    public func makeQueuedSession(for owner: UserID) -> AgentQueuedSession {
        AgentQueuedSession(session: makeSession(for: owner))
    }

    private init(
        agentId: AgentID,
        owner: UserID,
        behavior: AgentBehavior,
        toolBehavior: ToolBehavior,
        providerRegistry: ProviderRegistry,
        toolDefinition: ToolDefinition,
        sessionStateMode: SessionStateMode,
        traceRetentionPolicy: TraceRetentionPolicy,
    ) {
        self.agentId = agentId
        self.owner = owner
        self.behavior = behavior
        self.toolBehavior = toolBehavior
        self.providerRegistry = providerRegistry
        self.toolDefinition = toolDefinition
        self.sessionStateMode = sessionStateMode
        self.traceRetentionPolicy = traceRetentionPolicy
    }

    private func makeSessionToolDefinition(
        stateAccess: AgentSession.SessionStateAccess,
    ) -> ToolDefinition {
        let sessionStateConfig: SessionStateConfiguration? = switch sessionStateMode {
        case .disabled: nil
        case .readOnly(let config), .enabled(let config): config
        }
        let sessionToolRegistry = switch stateAccess {
        case .disabled:
            toolDefinition.registry
        case .readOnly(let state):
            toolDefinition.registry.adding(
                SessionStateBuiltins.makeReadOnlyTools(
                    state: state,
                    config: sessionStateConfig ?? SessionStateConfiguration(),
                ),
            )
        case .enabled(let state):
            toolDefinition.registry.adding(
                SessionStateBuiltins.makeTools(
                    state: state,
                    config: sessionStateConfig ?? SessionStateConfiguration(),
                ),
            )
        }
        return toolDefinition.replacing(registry: sessionToolRegistry)
    }

    private func makeSessionSystemPrompt(registry: ToolRegistry) -> String {
        var sections: [String] = []
        let trimmedBase = behavior.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            sections.append(trimmedBase)
        }
        if !registry.all.isEmpty {
            let guidance = toolBehavior.guidancePrompt.trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            if !guidance.isEmpty {
                sections.append(guidance)
            }
        }
        switch sessionStateMode {
        case .disabled:
            break
        case .readOnly(let configuration):
            let guidance = configuration.promptGuidance.trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            if !guidance.isEmpty {
                sections.append(guidance)
            }
            sections.append(SessionStateConfiguration.readOnlyPromptGuidance)
        case .enabled(let configuration):
            let guidance = configuration.promptGuidance.trimmingCharacters(
                in: .whitespacesAndNewlines,
            )
            if !guidance.isEmpty {
                sections.append(guidance)
            }
        }
        return sections.joined(separator: "\n\n")
    }
}
