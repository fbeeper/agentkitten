// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation

extension InferenceProvider where Provider == OpenAIInferenceProvider {
    /// OpenAI provider that reads the API key from the `OPENAI_API_KEY` environment variable.
    ///
    /// Suitable for CLI tools and the AgentKitten Playground.
    ///
    /// - Parameter model: The OpenAI model identifier. Defaults to `"gpt-4o"`.
    public static func openAI(model: String = "gpt-4o") -> Self {
        Self(
            OpenAIInferenceProvider(
                credentials: .key(EnvironmentAPIKeyProvider("OPENAI_API_KEY")),
                model: model,
            ),
        )
    }

    /// OpenAI provider with an explicit credential source.
    ///
    /// Pass any `APIKeyProviding` conformer. An environment variable reader,
    /// Keychain provider, network vault, or test stub.
    ///
    /// - Parameters:
    ///   - credentials: The credential source to use.
    ///   - model: The OpenAI model identifier. Defaults to `"gpt-4o"`.
    ///   - baseURL: The API base URL. Defaults to `https://api.openai.com/v1`.
    public static func openAI(
        credentials: some APIKeyProviding,
        model: String = "gpt-4o",
        baseURL: URL = OpenAIInferenceProvider.defaultBaseURL,
    ) -> Self {
        Self(
            OpenAIInferenceProvider(
                credentials: .key(credentials),
                model: model,
                baseURL: baseURL,
            ),
        )
    }
}
#endif
