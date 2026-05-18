// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Turn-scoped parameters passed alongside a message to ``InferenceSession/run(_:parameters:)``
/// and ``StructuredInferenceSession/generateStream(prompt:parameters:)``.
///
/// Bundles model generation settings, tool availability, and the tool step budget for this turn.
/// The user message is passed separately so these parameters can be forwarded
/// through the session's internal pipeline without carrying the message.
public struct InferenceRequestParameters: Sendable {
    /// Model generation parameters (temperature, token budget, etc.).
    public let configuration: InferenceConfiguration
    /// Turn-scoped budget for model-requested tool execution.
    public let toolStepBudget: ToolStepBudget
    /// Tool availability for this turn.
    public let toolSelection: ToolSelection
    /// Custom turn values visible to tool execution policy.
    public let toolExecutionContext: ToolExecutionContext
    /// Custom inference-domain values for this turn, readable by provider sessions.
    public let inferenceContext: InferenceContext

    /// Creates parameters with explicit configuration, tool availability, and policy context.
    public init(
        configuration: InferenceConfiguration = InferenceConfiguration(),
        toolStepBudget: ToolStepBudget = .budget(20),
        toolSelection: ToolSelection = .all,
        toolExecutionContext: ToolExecutionContext = .empty,
        inferenceContext: InferenceContext = .empty,
    ) {
        self.configuration = configuration
        self.toolStepBudget = toolStepBudget
        self.toolSelection = toolSelection
        self.toolExecutionContext = toolExecutionContext
        self.inferenceContext = inferenceContext
    }
}
