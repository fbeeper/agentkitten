// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

/// Overrides the Anthropic context-window size, in tokens.
///
/// By default the size is resolved from the Anthropic Models API, where `GET /models/{id}`
/// reports `max_input_tokens`. Compatible proxies or local servers may not expose that endpoint
/// or field, so `ContextUsage.contextSize` resolves to `.unknown` and percentage-based
/// automatic compaction can never trigger. Set this key to supply the window explicitly; it
/// takes precedence over endpoint discovery (and can override a window the endpoint reports).
///
/// Note: When the provider is created with `probesLMStudioMetadata`, discovery first probes
/// LM Studio's native metadata endpoint (which reports the served window), falling back to
/// `/models/{id}` only when that yields nothing. LM Studio serves the Messages API too.
///
/// Set it on `AgentBehavior` (phase scope, all turns) or `TurnOverrides` (single turn),
/// exactly like ``AnthropicModelKey``.
///
/// Example:
/// ```swift
/// var behavior = AgentBehavior(systemPrompt: "You are a helpful assistant.")
/// behavior.phaseBehaviors.base[AnthropicContextWindowKey.self] = 4096
/// ```
public struct AnthropicContextWindowKey: ExecutionConfigurationKey {
    /// The context-window size in tokens (e.g. `4096`).
    public typealias Value = Int
    public static let domains: Set<ExecutionConfigurationDomain> = [.inference]
}
#endif
