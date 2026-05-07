// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Defines the tool set, execution policy, and lifecycle hooks for an agent.
///
/// `ToolDefinition` is the definition-time bundle for structural tool concerns:
/// it pairs the tools an agent may invoke with the policy that governs when each
/// call is allowed to execute, and optional hooks that intercept execution.
/// All are immutable after creation.
///
/// At session creation time, ``Agent/makeSession(for:)`` combines a
/// `ToolDefinition` with a freshly created ``ToolApprovalGate`` to produce
/// the ``ToolRuntime`` passed to inference providers.
public struct ToolDefinition: Sendable {
    let registry: ToolRegistry
    let executionPolicy: AnyToolExecutionPolicy
    /// Hooks that intercept tool calls before and after execution, in declaration order.
    public let hooks: [AnyToolHook]

    /// Creates a tool configuration with the given tools, execution policy, and hooks.
    ///
    /// Duplicate tool names or hook names trigger a `preconditionFailure`.
    ///
    /// - Parameters:
    ///   - tools: Tools the model may invoke.
    ///   - executionPolicy: The policy consulted before any tool call executes.
    ///   - hooks: Lifecycle hooks that intercept tool calls in declaration order.
    public init(
        tools: [AnyAgentTool] = [],
        executionPolicy: some ToolExecutionPolicy = AutoApprovePolicy(),
        hooks: [AnyToolHook] = []
    ) {
        self.registry = ToolRegistry(tools)
        self.executionPolicy = AnyToolExecutionPolicy(executionPolicy)
        var seen = Set<String>()
        for hook in hooks {
            precondition(
                seen.insert(hook.name).inserted,
                "Duplicate hook name '\(hook.name)' — each hook must have a unique name."
            )
        }
        self.hooks = hooks
    }

    /// No tools. Default for agents that do not use tools.
    public static let noTools = ToolDefinition()

    func replacing(registry: ToolRegistry) -> ToolDefinition {
        ToolDefinition(registry: registry, executionPolicy: executionPolicy, hooks: hooks)
    }

    /// Creates a configuration from an already-built registry, avoiding a redundant rebuild.
    private init(registry: ToolRegistry, executionPolicy: AnyToolExecutionPolicy, hooks: [AnyToolHook]) {
        self.registry = registry
        self.executionPolicy = executionPolicy
        self.hooks = hooks
    }
}
