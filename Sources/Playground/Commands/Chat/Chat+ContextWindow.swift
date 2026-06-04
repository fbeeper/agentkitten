// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import ArgumentParser
#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenAnthropicInference
import AgentKittenOpenAIInference
#endif

extension Playground.Chat {
    /// Validates the `--context-window` override.
    ///
    /// The value must be positive and is only honored by providers that expose a context-window
    /// key (OpenAI and Anthropic). Rejecting it for other providers avoids a silent no-op.
    func validateContextWindow() throws {
        guard let contextWindow else {
            return
        }
        if contextWindow <= 0 {
            throw ValidationError("--context-window must be positive.")
        }
        guard providerSupportsContextWindow else {
            throw ValidationError("--context-window is only supported for the openai and anthropic providers.")
        }
    }

    /// Whether the selected provider honors the `--context-window` override.
    var providerSupportsContextWindow: Bool {
        #if canImport(Darwin) || canImport(FoundationNetworking)
        return provider == .openai || provider == .anthropic
        #else
        return false
        #endif
    }

    /// Seeds the per-turn context-window override key for providers that support it,
    /// so `/usage` and percent-based compaction work against endpoints that don't
    /// report a window (e.g. LM Studio).
    func applyContextWindow(to base: inout PhaseBehavior) {
        guard let contextWindow, providerSupportsContextWindow else {
            return
        }
        #if canImport(Darwin) || canImport(FoundationNetworking)
        switch provider {
        case .openai:
            base[OpenAIContextWindowKey.self] = contextWindow
        case .anthropic:
            base[AnthropicContextWindowKey.self] = contextWindow
        default:
            break
        }
        #endif
    }
}
