// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import Foundation
#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenAnthropicInference
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
        openAIBaseURL: URL? = nil,
        openAIModel: String = "gpt-4o",
    ) throws -> (registry: ProviderRegistry, compactionProvider: ProviderReference?) {
        let registry = try makeRegistry(
            for: defaultOption,
            openAIBaseURL: openAIBaseURL,
            openAIModel: openAIModel,
        )
        guard let compactionOption, compactionOption != defaultOption else {
            return (registry, nil)
        }
        let updatedRegistry: ProviderRegistry
        let reference: ProviderReference
        switch compactionOption {
        case .mock:
            updatedRegistry = registry.registering(InferenceProvider.mock())
            reference = .ofType(InferenceProvider<MockInferenceProvider>.self)
        #if canImport(Darwin) || canImport(FoundationNetworking)
        case .anthropic:
            updatedRegistry = registry.registering(InferenceProvider.anthropic())
            reference = .ofType(InferenceProvider<AnthropicInferenceProvider>.self)
        case .openai:
            let provider = openAIInferenceProvider(baseURL: openAIBaseURL, model: openAIModel)
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
        openAIBaseURL: URL? = nil,
        openAIModel: String = "gpt-4o",
    ) throws -> ProviderRegistry {
        switch option {
        case .mock:
            return ProviderRegistry(default: InferenceProvider.mock())
        #if canImport(Darwin) || canImport(FoundationNetworking)
        case .anthropic:
            return ProviderRegistry(default: InferenceProvider.anthropic())
        case .openai:
            return ProviderRegistry(default: openAIInferenceProvider(baseURL: openAIBaseURL, model: openAIModel))
        #endif
        #if canImport(FoundationModels)
        case .apple:
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
        openAIBaseURL: URL? = nil,
        openAIModel: String = "gpt-4o",
    ) throws -> ProviderRegistry {
        switch option {
        case .mock:
            return ProviderRegistry(default: MockInferenceProvider(
                structuredResponses: [#"{"verdict":"pass"}"#],
            ))
        #if canImport(Darwin) || canImport(FoundationNetworking)
        case .anthropic:
            return ProviderRegistry(default: InferenceProvider.anthropic())
        case .openai:
            return ProviderRegistry(default: openAIInferenceProvider(baseURL: openAIBaseURL, model: openAIModel))
        #endif
        #if canImport(FoundationModels)
        case .apple:
            if #available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *) {
                return ProviderRegistry(default: InferenceProvider.apple())
            }
            throw PlaygroundError.appleIntelligenceRequiresMacOS26
        #endif
        }
    }

    #if canImport(Darwin) || canImport(FoundationNetworking)
    static func openAIInferenceProvider(
        baseURL: URL?,
        model: String,
    ) -> InferenceProvider<OpenAIInferenceProvider> {
        if let url = baseURL {
            return InferenceProvider.lmStudio(baseURL: url, model: model)
        }
        return InferenceProvider.openAI(model: model)
    }
    #endif
}
