// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import Foundation
#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenAnthropicInference
import AgentKittenInferenceSupport
import AgentKittenOpenAIInference
#endif
import AgentKittenAppleInference

/// Factory for building provider registries used by Playground commands.
enum PlaygroundProviderFactory {
    /// Returns a provider registry plus provider reference for an alternate compaction provider.
    ///
    /// When `compactionOption` is `nil` or matches `defaultOption`, the returned
    /// reference is `nil` and the default provider handles compaction too.
    static func makeRegistry(
        default defaultOption: ProviderOption,
        compaction compactionOption: ProviderOption?,
        endpoint: ProviderEndpointConfiguration = .default,
    ) throws -> (registry: ProviderRegistry, compactionProvider: ProviderReference?) {
        let registry = try makeRegistry(
            for: defaultOption,
            endpoint: endpoint,
        )
        guard let compactionOption, compactionOption != defaultOption else {
            return (registry, nil)
        }
        let updatedRegistry: ProviderRegistry
        let reference: ProviderReference
        switch compactionOption {
        case .mock:
            try validateEndpointOptions(endpoint, for: compactionOption, allowingModel: false)
            updatedRegistry = registry.registering(InferenceProvider.mock())
            reference = .ofType(InferenceProvider<MockInferenceProvider>.self)
        #if canImport(Darwin) || canImport(FoundationNetworking)
        case .anthropic:
            updatedRegistry = registry.registering(anthropicInferenceProvider(configuration: endpoint))
            reference = .ofType(InferenceProvider<AnthropicInferenceProvider>.self)
        case .openai:
            let provider = openAIInferenceProvider(configuration: endpoint)
            updatedRegistry = registry.registering(provider)
            reference = .ofType(InferenceProvider<OpenAIInferenceProvider>.self)
        #endif
        #if canImport(FoundationModels)
        case .apple:
            if #available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *) {
                let provider = InferenceProvider.apple()
                updatedRegistry = registry.registering(provider)
                reference = .ofType(InferenceProvider<AppleInferenceProvider>.self)
            } else {
                throw PlaygroundError.appleIntelligenceRequiresMacOS26
            }
        #endif
        }
        return (updatedRegistry, reference)
    }

    /// Returns a ``ProviderRegistry`` for the given provider option.
    ///
    /// Throws ``PlaygroundError`` when the Apple provider is requested but unavailable.
    ///
    /// - Parameter option: The provider to use.
    static func makeRegistry(
        for option: ProviderOption,
        endpoint: ProviderEndpointConfiguration = .default,
    ) throws -> ProviderRegistry {
        switch option {
        case .mock:
            try validateEndpointOptions(endpoint, for: option, allowingModel: false)
            return ProviderRegistry(default: InferenceProvider.mock())
        #if canImport(Darwin) || canImport(FoundationNetworking)
        case .anthropic:
            return ProviderRegistry(default: anthropicInferenceProvider(configuration: endpoint))
        case .openai:
            return ProviderRegistry(default: openAIInferenceProvider(configuration: endpoint))
        #endif
        #if canImport(FoundationModels)
        case .apple:
            try validateEndpointOptions(endpoint, for: option, allowingModel: false)
            if #available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *) {
                return ProviderRegistry(default: InferenceProvider.apple())
            }
            throw PlaygroundError.appleIntelligenceRequiresMacOS26
        #endif
        }
    }

    /// Returns a ``ProviderRegistry`` suitable for judge-driven structured validation.
    ///
    /// The mock judge provider uses a canned structured pass verdict so Playground
    /// can demonstrate `JudgeValidator` without requiring a network provider.
    static func makeJudgeRegistry(
        for option: ProviderOption,
        endpoint: ProviderEndpointConfiguration = .default,
    ) throws -> ProviderRegistry {
        switch option {
        case .mock:
            try validateEndpointOptions(endpoint, for: option, allowingModel: false)
            return ProviderRegistry(default: MockInferenceProvider(
                structuredResponses: [#"{"verdict":"pass"}"#],
            ))
        #if canImport(Darwin) || canImport(FoundationNetworking)
        case .anthropic:
            return ProviderRegistry(default: anthropicInferenceProvider(configuration: endpoint))
        case .openai:
            return ProviderRegistry(default: openAIInferenceProvider(configuration: endpoint))
        #endif
        #if canImport(FoundationModels)
        case .apple:
            try validateEndpointOptions(endpoint, for: option, allowingModel: false)
            if #available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *) {
                return ProviderRegistry(default: InferenceProvider.apple())
            }
            throw PlaygroundError.appleIntelligenceRequiresMacOS26
        #endif
        }
    }

    #if canImport(Darwin) || canImport(FoundationNetworking)
    static func anthropicInferenceProvider(
        configuration: ProviderEndpointConfiguration,
    ) -> InferenceProvider<AnthropicInferenceProvider> {
        if configuration.skipCredential {
            return InferenceProvider(
                AnthropicInferenceProvider(
                    credentials: .noCredential,
                    model: configuration.model(default: "claude-sonnet-4-5"),
                    baseURL: configuration.baseURL ?? AnthropicInferenceProvider.defaultBaseURL,
                    probesLMStudioMetadata: configuration.lmStudio,
                ),
            )
        }
        if let url = configuration.baseURL {
            return InferenceProvider(
                AnthropicInferenceProvider(
                    credentials: .key(EnvironmentAPIKeyProvider("ANTHROPIC_API_KEY")),
                    model: configuration.model(default: "claude-sonnet-4-5"),
                    baseURL: url,
                    probesLMStudioMetadata: configuration.lmStudio,
                ),
            )
        }
        return InferenceProvider.anthropic(model: configuration.model(default: "claude-sonnet-4-5"))
    }

    static func openAIInferenceProvider(
        configuration: ProviderEndpointConfiguration,
    ) -> InferenceProvider<OpenAIInferenceProvider> {
        if configuration.skipCredential {
            return InferenceProvider(
                OpenAIInferenceProvider(
                    credentials: .noCredential,
                    model: configuration.model(default: "gpt-4o"),
                    baseURL: configuration.baseURL ?? OpenAIInferenceProvider.defaultBaseURL,
                    probesLMStudioMetadata: configuration.lmStudio,
                ),
            )
        }
        if let url = configuration.baseURL {
            return InferenceProvider(
                OpenAIInferenceProvider(
                    credentials: .key(EnvironmentAPIKeyProvider("OPENAI_API_KEY")),
                    model: configuration.model(default: "gpt-4o"),
                    baseURL: url,
                    probesLMStudioMetadata: configuration.lmStudio,
                ),
            )
        }
        return InferenceProvider.openAI(model: configuration.model(default: "gpt-4o"))
    }
    #endif

    static func validateEndpointOptions(
        _ configuration: ProviderEndpointConfiguration,
        for provider: ProviderOption,
        allowingModel: Bool,
    ) throws {
        var unsupported: [String] = []
        if !allowingModel, configuration.model != nil {
            unsupported.append("--model")
        }
        if configuration.baseURL != nil {
            unsupported.append("--base-url")
        }
        if configuration.skipCredential {
            unsupported.append("--skip-credential")
        }
        if configuration.lmStudio {
            unsupported.append("--lmstudio")
        }
        if !unsupported.isEmpty {
            throw PlaygroundError.unsupportedProviderEndpointOptions(
                provider: provider.rawValue,
                options: unsupported,
            )
        }
    }
}
