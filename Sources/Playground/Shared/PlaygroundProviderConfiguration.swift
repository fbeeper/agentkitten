// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenAnthropicInference
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
    ) throws -> (registry: ProviderRegistry, compactionProvider: ProviderReference?) {
        let registry = try makeRegistry(for: defaultOption)
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
    static func makeRegistry(for option: ProviderOption) throws -> ProviderRegistry {
        switch option {
        case .mock:
            return ProviderRegistry(default: InferenceProvider.mock())
        #if canImport(Darwin) || canImport(FoundationNetworking)
        case .anthropic:
            return ProviderRegistry(default: InferenceProvider.anthropic())
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
    static func makeJudgeRegistry(for option: ProviderOption) throws -> ProviderRegistry {
        switch option {
        case .mock:
            return ProviderRegistry(default: MockInferenceProvider(
                structuredResponses: [#"{"verdict":"pass"}"#],
            ))
        #if canImport(Darwin) || canImport(FoundationNetworking)
        case .anthropic:
            return ProviderRegistry(default: InferenceProvider.anthropic())
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
}
