// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

/// Overrides the OpenAI context-window size, in tokens.
///
/// By default the size is resolved from `/models/{id}` metadata. Servers that don't report a
/// window leave `ContextUsage.contextSize` as `.unknown`, so percentage-based automatic
/// compaction can never trigger. Set this key to supply the window explicitly; it takes
/// precedence over endpoint discovery (and can override a window the endpoint reports).
///
/// Note: When the provider is created with `probesLMStudioMetadata`, discovery first probes
/// LM Studio's native metadata endpoint (which reports the served window), falling back to
/// `/models/{id}` only when that yields nothing.
///
/// Set it on `AgentBehavior` (phase scope, all turns) or `TurnOverrides` (single turn),
/// exactly like ``OpenAIModelKey``.
///
/// Example:
/// ```swift
/// var behavior = AgentBehavior(systemPrompt: "You are a helpful assistant.")
/// behavior.phaseBehaviors.base[OpenAIContextWindowKey.self] = 4096
/// ```
public struct OpenAIContextWindowKey: ExecutionConfigurationKey {
    /// The context-window size in tokens (e.g. `4096`).
    public typealias Value = Int
    public static let domains: Set<ExecutionConfigurationDomain> = [.inference]
}
#endif
