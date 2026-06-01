// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

/// Overrides the OpenAI model identifier on a per-turn basis.
///
/// Set this key on ``AgentBehavior`` to change the default model for all turns,
/// or on ``TurnOverrides`` to override for a single turn. When absent, the
/// model configured on ``OpenAIInferenceProvider`` is used.
///
/// Example:
/// ```swift
/// var behavior = AgentBehavior(systemPrompt: "You are a helpful assistant.")
/// behavior.phaseBehaviors.base[OpenAIModelKey.self] = "gpt-4o-mini"
/// ```
public struct OpenAIModelKey: ExecutionConfigurationKey {
    /// The OpenAI model identifier string (e.g. `"gpt-4o"`).
    public typealias Value = String
    public static let domains: Set<ExecutionConfigurationDomain> = [.inference]
}
#endif
