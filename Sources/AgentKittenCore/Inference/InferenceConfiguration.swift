// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Turn-scoped budget for model-requested tool execution.
public enum ToolStepBudget: Sendable, Equatable, Hashable {
    /// Tool execution is disabled for the turn.
    case disabled

    /// Tool execution is allowed up to the given number of calls.
    case budget(UInt)

    /// Tool execution is allowed without a turn-scoped limit.
    case unbounded
}

/// Parameters that control how the model generates a response.
///
/// Defaults are intentionally practical for the common agent case. Override
/// when you need more deterministic output or a larger token budget.
///
/// Tool execution limits live in ``ToolBehavior/defaultStepBudget`` and can be
/// overridden per turn via ``TurnOverrides/toolStepBudget``.
public struct InferenceConfiguration: Sendable, Equatable, Hashable {
    /// Sampling temperature. Higher values increase output randomness.
    ///
    /// Range: `0.0` (deterministic) to `1.0` (highly random). Default: `0.7`.
    public let temperature: Double

    /// Maximum number of tokens to generate in the response.
    ///
    /// Use to protect against unexpectedly verbose output. Default: `4096`.
    public let maxTokens: Int

    /// Creates a configuration with the given parameters.
    public init(
        temperature: Double = 0.7,
        maxTokens: Int = 4096,
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}
