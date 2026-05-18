// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Stable runtime dependencies needed to execute model-requested tool calls.
///
/// Providers receive a ``ToolRuntime`` when a conversation session is created.
/// It exposes the registered tools for provider bridging plus stable execution
/// services shared across turns. Per-turn tool budgeting and invocation state
/// live in ``ToolTurnRuntime`` actors created from this runtime.
public struct ToolRuntime: Sendable {
    package let toolRegistry: ToolRegistry
    private let executor: ToolExecutor
    private let executionPolicy: AnyToolExecutionPolicy
    private let hooks: [AnyToolHook]

    /// Suspends pending tool calls that require interactive approval.
    public let approvalGate: ToolApprovalGate
    /// Schema description used for the injected rationale field when bridging tools to a provider.
    public let rationaleSchemaDescription: String

    /// Creates a tool runtime with explicit execution and approval dependencies.
    private init(
        executor: ToolExecutor,
        executionPolicy: some ToolExecutionPolicy,
        hooks: [AnyToolHook],
        approvalGate: ToolApprovalGate = ToolApprovalGate(),
        rationaleSchemaDescription: String = ToolRationale.schemaDescription,
    ) {
        toolRegistry = executor.registry
        self.executor = executor
        self.executionPolicy = AnyToolExecutionPolicy(executionPolicy)
        self.hooks = hooks
        self.approvalGate = approvalGate
        self.rationaleSchemaDescription = rationaleSchemaDescription
    }

    /// Creates a tool runtime from a tool configuration plus runtime controls.
    ///
    /// - Parameters:
    ///   - configuration: Declarative tool setup used to derive the registry, policy, and hooks.
    ///   - rationaleSchemaDescription: Schema description for the injected rationale field.
    ///     Defaults to AgentKitten's built-in description; pass a custom value when the agent's
    ///     ``ToolBehavior/rationaleGuidance`` is overridden.
    ///   - approvalGate: The gate that suspends tool calls requiring interactive approval.
    public init(
        configuration: ToolDefinition,
        rationaleSchemaDescription: String = ToolRationale.schemaDescription,
        approvalGate: ToolApprovalGate = ToolApprovalGate(),
    ) {
        self.init(
            executor: ToolExecutor(registry: configuration.registry),
            executionPolicy: configuration.executionPolicy,
            hooks: configuration.hooks,
            approvalGate: approvalGate,
            rationaleSchemaDescription: rationaleSchemaDescription,
        )
    }

    /// The registered tools, exposed for provider-specific tool bridging.
    public var allTools: [AnyAgentTool] {
        toolRegistry.all
    }

    /// Returns registered tools allowed by `selection`.
    public func tools(matching selection: ToolSelection) -> [AnyAgentTool] {
        toolRegistry.tools(matching: selection)
    }

    /// Creates a turn-scoped tool runtime with its own independent budget and policy context.
    public func makeTurnRuntime(
        toolStepBudget: ToolStepBudget,
        context: ToolExecutionContext = .empty,
        toolSelection: ToolSelection = .all,
    ) -> ToolTurnRuntime {
        ToolTurnRuntime(
            executor: executor,
            executionPolicy: executionPolicy,
            hooks: hooks,
            approvalGate: approvalGate,
            toolStepBudget: toolStepBudget,
            context: context,
            toolSelection: toolSelection,
        )
    }
}

/// Per-turn tool execution runtime derived from a stable ``ToolRuntime``.
///
/// Each model turn creates a fresh `ToolTurnRuntime`. The actor owns only
/// turn-scoped mutable state, such as the remaining tool-step budget, while
/// sharing stable execution services from its parent ``ToolRuntime``.
public actor ToolTurnRuntime {
    private let executor: ToolExecutor
    private let executionPolicy: AnyToolExecutionPolicy
    private let hooks: [AnyToolHook]
    private let approvalGate: ToolApprovalGate
    private let context: ToolExecutionContext
    private let toolSelection: ToolSelection
    private var toolStepBudget: ToolStepBudget

    package init(
        executor: ToolExecutor,
        executionPolicy: AnyToolExecutionPolicy,
        hooks: [AnyToolHook],
        approvalGate: ToolApprovalGate,
        toolStepBudget: ToolStepBudget,
        context: ToolExecutionContext,
        toolSelection: ToolSelection,
    ) {
        self.executor = executor
        self.executionPolicy = executionPolicy
        self.hooks = hooks
        self.approvalGate = approvalGate
        self.context = context
        self.toolSelection = toolSelection
        self.toolStepBudget = toolStepBudget
    }

    /// Resolves policy and approval, enforces turn budget, runs hooks, and executes the tool.
    public func invoke(
        _ call: PendingToolCall,
        onApprovalRequired: @escaping @Sendable (PendingToolCall) async -> Void,
        onHookFired: @escaping @Sendable (ToolHookInvocationInfo) async -> Void = { _ in },
    ) async -> ToolCallOutcome {
        do {
            guard toolSelection.allows(toolName: call.name) else {
                return .failure(.denied(reason: toolDeniedReason(for: call.name)))
            }
            guard hasRemainingStepCapacity else {
                return .failure(.stepLimitExceeded)
            }
            let decision = try await resolveExecutionDecision(
                for: call,
                onApprovalRequired: onApprovalRequired,
            )
            if case .deny(let reason) = decision {
                return .failure(.denied(reason: reason))
            }

            consumeStep()
            let preparedCall = try await runBeforeHooks(for: call, onHookFired: onHookFired)
            let content = try await executor.execute(preparedCall)
            return await runAfterHooks(
                for: preparedCall,
                outcome: .success(content: content),
                onHookFired: onHookFired,
            )
        } catch {
            return .failure(.execution(message: String(describing: error)))
        }
    }

    private func runBeforeHooks(
        for call: PendingToolCall,
        onHookFired: @escaping @Sendable (ToolHookInvocationInfo) async -> Void,
    ) async throws -> PendingToolCall {
        var current = call
        for hook in hooks where hook.phases.contains(.before) {
            let transformed = try await hook.beforeExecute(current, context: context)
            await onHookFired(ToolHookInvocationInfo(
                callID: call.id,
                toolName: call.name,
                hookName: hook.name,
                phase: ToolHookPhase.before.traceSnapshot,
                transformed: transformed.argumentsJSON != current.argumentsJSON,
            ))
            current = transformed
        }
        return current
    }

    private func runAfterHooks(
        for call: PendingToolCall,
        outcome: ToolCallOutcome,
        onHookFired: @escaping @Sendable (ToolHookInvocationInfo) async -> Void,
    ) async -> ToolCallOutcome {
        var current = outcome
        for hook in hooks where hook.phases.contains(.after) {
            let next = await hook.afterExecute(call, outcome: current, context: context)
            await onHookFired(ToolHookInvocationInfo(
                callID: call.id,
                toolName: call.name,
                hookName: hook.name,
                phase: ToolHookPhase.after.traceSnapshot,
                transformed: next != current,
            ))
            current = next
        }
        return current
    }

    private func toolDeniedReason(for name: String) -> String {
        switch toolSelection {
        case .disabled:
            AgentKittenLocalization.string("tools.disabledReason")
        case .including, .excluding:
            AgentKittenLocalization.formattedString("tools.unavailableReasonFormat", name)
        case .all:
            preconditionFailure("Tool selection denied a tool while all tools are available.")
        }
    }

    private var hasRemainingStepCapacity: Bool {
        switch toolStepBudget {
        case .disabled:
            return false
        case .budget(let remainingSteps):
            return remainingSteps > 0
        case .unbounded:
            return true
        }
    }

    private func consumeStep() {
        switch toolStepBudget {
        case .disabled:
            return
        case .budget(let remainingSteps):
            toolStepBudget = .budget(remainingSteps - 1)
        case .unbounded:
            return
        }
    }

    private func resolveExecutionDecision(
        for call: PendingToolCall,
        onApprovalRequired: @escaping @Sendable (PendingToolCall) async -> Void,
    ) async throws -> ToolExecutionDecision {
        let decision = await executionPolicy.resolve(call: call, context: context)
        guard case .requiresApproval = decision else {
            return decision
        }

        try await approvalGate.register(
            callID: call.id,
            traceContext: context.traceSnapshot,
        )
        await onApprovalRequired(call)

        return try await withTaskCancellationHandler(
            operation: {
                let approvalDecision = try await approvalGate.waitForResolution(callID: call.id)
                try Task.checkCancellation()
                switch approvalDecision {
                case .approved:
                    return .execute
                case .denied(let reason):
                    return .deny(reason: reason)
                }
            },
            onCancel: {
                Task {
                    await self.approvalGate.cancel(callID: call.id)
                }
            },
        )
    }
}
