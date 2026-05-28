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
        Self(OpenAIInferenceProvider(
            credentials: EnvironmentAPIKeyProvider("OPENAI_API_KEY"),
            model: model,
        ))
    }

    /// OpenAI provider with an explicit credential source.
    ///
    /// Pass any ``APIKeyProviding`` conformer — an environment variable reader,
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
        Self(OpenAIInferenceProvider(
            credentials: credentials,
            model: model,
            baseURL: baseURL,
        ))
    }

    #if canImport(Security)
    /// OpenAI provider that reads the API key from the system Keychain.
    ///
    /// Recommended for app targets where storing secrets in environment variables
    /// is not appropriate.
    ///
    /// - Parameters:
    ///   - service: Keychain service name (typically the app's bundle ID).
    ///   - account: Keychain account name distinguishing multiple keys under the same service.
    ///   - model: The OpenAI model identifier. Defaults to `"gpt-4o"`.
    public static func openAI(
        keychain service: String,
        account: String,
        model: String = "gpt-4o",
    ) -> Self {
        Self(OpenAIInferenceProvider(
            credentials: KeychainAPIKeyProvider(service: service, account: account),
            model: model,
        ))
    }
    #endif

    /// Provider targeting an LM Studio server (or any other local OpenAI-compatible endpoint).
    ///
    /// LM Studio exposes an OpenAI-compatible REST API and accepts any non-empty string as the
    /// API key. This factory passes a `"lm-studio"` placeholder so the `Authorization` header
    /// is well-formed without requiring a real credential.
    ///
    /// ```swift
    /// let provider = InferenceProvider.lmStudio(
    ///     baseURL: URL(string: "http://localhost:1234/v1")!,
    ///     model: "qwen2.5-coder-7b-instruct"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - baseURL: The LM Studio (or compatible server) base URL.
    ///   - model: The model identifier as reported by the local server.
    public static func lmStudio(baseURL: URL, model: String) -> Self {
        Self(OpenAIInferenceProvider(
            credentials: MockAPIKeyProvider("lm-studio"),
            model: model,
            baseURL: baseURL,
        ))
    }
}
#endif
