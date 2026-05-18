// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import OSLog

private let logger = Logger(subsystem: "AgentKittenCore", category: "ProviderRegistry")

/// A validated registry of inference providers available to an agent.
///
/// Internal conversation configuration refers to these providers through
/// ``ProviderReference``.
public struct ProviderRegistry: Sendable {
    private let defaultProvider: AnyInferenceProvider
    private var providers: [ObjectIdentifier: AnyInferenceProvider]

    /// Creates a registry from the given default provider.
    public init<Provider: InferenceProviding>(
        default provider: Provider,
    ) {
        defaultProvider = AnyInferenceProvider(provider)
        providers = [:]
    }

    /// Registers a provider for later lookup by its concrete type.
    ///
    /// Provider registration is one-instance-per-type. Registering the same
    /// type again replaces the prior registration.
    public func registering<Provider: InferenceProviding>(
        _ provider: Provider,
    ) -> Self {
        var registry = self
        let erasedProvider = AnyInferenceProvider(provider)
        if registry.providers.updateValue(
            erasedProvider,
            forKey: erasedProvider.providerObjectIdentifier,
        ) != nil {
            logger.info("Replacing existing provider registration for type key.")
        }
        return registry
    }

    func resolve(_ reference: ProviderReference) -> AnyInferenceProvider {
        guard let identifier = reference.providerObjectIdentifier else {
            return defaultProvider
        }

        guard let provider = providers[identifier] else {
            logger.info("Falling back to the default provider.")
            return defaultProvider
        }
        return provider
    }
}
