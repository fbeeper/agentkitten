// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A type-erased wrapper around a ``ToolHook`` conformance.
public struct AnyToolHook: Sendable {
    /// The hook's declared name.
    public let name: String
    /// The lifecycle phases this hook participates in.
    public let phases: Set<ToolHookPhase>

    private let beforeHandler: @Sendable (PendingToolCall, ToolExecutionContext) async throws -> PendingToolCall
    private let afterHandler: @Sendable (PendingToolCall, ToolCallOutcome, ToolExecutionContext) async -> ToolCallOutcome
    // swiftlint:disable:previous line_length

    /// Creates a type-erased wrapper from a concrete ``ToolHook``.
    public init<H: ToolHook>(_ hook: H) {
        self.name = hook.name
        self.phases = hook.phases
        self.beforeHandler = { call, context in
            try await hook.beforeExecute(call, context: context)
        }
        self.afterHandler = { call, outcome, context in
            await hook.afterExecute(call, outcome: outcome, context: context)
        }
    }

    func beforeExecute(_ call: PendingToolCall, context: ToolExecutionContext) async throws -> PendingToolCall {
        try await beforeHandler(call, context)
    }

    func afterExecute(
        _ call: PendingToolCall,
        outcome: ToolCallOutcome,
        context: ToolExecutionContext,
    ) async -> ToolCallOutcome {
        await afterHandler(call, outcome, context)
    }
}
