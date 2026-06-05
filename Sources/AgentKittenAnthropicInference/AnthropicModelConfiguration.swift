// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

/// A pending tool call captured from the SSE stream.
struct PendingSSEToolCall {
    let id: String
    let name: String
    let argsJSON: String
}

/// Overrides the Anthropic model identifier on a per-turn basis.
///
/// Set this key on `AgentBehavior` to change the default model for all turns,
/// or on `TurnOverrides` to override for a single turn. When absent, the
/// model configured on ``AnthropicInferenceProvider`` is used.
///
/// Example:
/// ```swift
/// var behavior = AgentBehavior(systemPrompt: "You are a helpful assistant.")
/// behavior.phaseBehaviors.base[AnthropicModelKey.self] = "claude-opus-4-5"
/// ```
public struct AnthropicModelKey: ExecutionConfigurationKey {
    /// The Anthropic model identifier string (e.g. `"claude-opus-4-5"`).
    public typealias Value = String
    public static let domains: Set<ExecutionConfigurationDomain> = [.inference]
}
#endif
