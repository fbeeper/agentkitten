// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation

extension InferenceProvider where Provider == AnthropicInferenceProvider {
    /// Anthropic provider that reads the API key from the `ANTHROPIC_API_KEY` environment variable.
    ///
    /// Suitable for CLI tools and the AgentKitten Playground.
    ///
    /// - Parameters:
    ///   - model: The Anthropic model identifier. Defaults to `"claude-sonnet-4-5"`.
    public static func anthropic(model: String = "claude-sonnet-4-5") -> Self {
        Self(AnthropicInferenceProvider(
            credentials: .key(EnvironmentAPIKeyProvider("ANTHROPIC_API_KEY")),
            model: model,
        ))
    }

    /// Anthropic provider with an explicit credential source.
    ///
    /// Pass any ``APIKeyProviding`` conformer — an environment variable reader,
    /// Keychain provider, network vault, or test stub.
    ///
    /// - Parameters:
    ///   - credentials: The credential source to use.
    ///   - model: The Anthropic model identifier. Defaults to `"claude-sonnet-4-5"`.
    ///   - baseURL: The API base URL. Defaults to ``AnthropicInferenceProvider/defaultBaseURL``.
    public static func anthropic(
        credentials: some APIKeyProviding,
        model: String = "claude-sonnet-4-5",
        baseURL: URL = AnthropicInferenceProvider.defaultBaseURL,
    ) -> Self {
        Self(AnthropicInferenceProvider(
            credentials: .key(credentials),
            model: model,
            baseURL: baseURL,
        ))
    }
}
#endif
