// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Execution behavior settings for one agent phase.
public struct PhaseBehavior: Sendable {
    /// The provider used for this phase.
    public let provider: ProviderReference
    /// The inference configuration used for this phase.
    public let inferenceConfiguration: InferenceConfiguration
    private var customValues: [String: ExecutionConfigurationCustomValue] = [:]

    /// Creates phase behavior settings.
    ///
    /// - Parameters:
    ///   - provider: Provider reference for this phase. Defaults to the agent default provider.
    ///   - inferenceConfiguration: Inference configuration for this phase.
    public init(
        provider: ProviderReference = .default,
        inferenceConfiguration: InferenceConfiguration = .init(),
    ) {
        self.provider = provider
        self.inferenceConfiguration = inferenceConfiguration
    }

    /// Accesses a typed phase-scoped custom value.
    public subscript<Key: ExecutionConfigurationKey>(_ key: Key.Type) -> Key.Value? {
        get {
            customValues[Key.id]?.value as? Key.Value
        }
        set {
            if let newValue {
                customValues[Key.id] = ExecutionConfigurationCustomValue(
                    domains: Key.domains,
                    value: newValue,
                )
            } else {
                customValues.removeValue(forKey: Key.id)
            }
        }
    }

    var inferenceContext: InferenceContext {
        InferenceContext(customValues: customValues.filter { $0.value.domains.contains(.inference) })
    }
}

extension PhaseBehavior {
    var storedCustomValues: [String: ExecutionConfigurationCustomValue] {
        customValues
    }
}
