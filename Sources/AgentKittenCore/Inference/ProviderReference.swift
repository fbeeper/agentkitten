// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A provider selection reference carried by conversation configuration.
public struct ProviderReference: Sendable, Equatable, Hashable {
    // Keep the enum private so the public API stays `.default` / `.ofType(...)`
    // instead of exposing raw `ObjectIdentifier` construction. That makes the
    // type-key storage an implementation detail rather than part of the ABI.
    private enum Storage: Sendable, Equatable, Hashable {
        case `default`
        case providerType(ObjectIdentifier, String)
    }

    private let storage: Storage

    /// Use the agent's default provider.
    public static let `default` = Self(storage: .default)

    /// Use the provider registered for the given concrete provider type.
    ///
    /// This follows Swift's `EnvironmentKey` pattern: the provider type is the
    /// lookup key. Distinct registered provider identities such as Anthropic
    /// Haiku vs. Anthropic Sonnet can still use wrapper types, while
    /// conversation-level inference settings belong on configuration types.
    public static func ofType<Provider: InferenceProviding>(
        _ type: Provider.Type,
    ) -> Self {
        Self(storage: .providerType(
            ObjectIdentifier(type),
            String(describing: type),
        ))
    }

    var providerObjectIdentifier: ObjectIdentifier? {
        switch storage {
        case .default:
            nil
        case .providerType(let identifier, _):
            identifier
        }
    }

    var providerTypeName: String? {
        switch storage {
        case .default:
            nil
        case .providerType(_, let name):
            name
        }
    }
}
