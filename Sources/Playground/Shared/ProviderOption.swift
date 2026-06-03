// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import ArgumentParser
import Foundation

/// The inference provider to use for a Playground command.
enum ProviderOption: String, CaseIterable, ExpressibleByArgument {
    /// A mock inference model used as a test double. Not practical, mostly a filler fallback.
    case mock

    #if canImport(FoundationModels)
    /// Apple Foundation Models
    case apple
    #endif

    #if canImport(Darwin) || canImport(FoundationNetworking)
    /// Anthropic API
    case anthropic
    /// OpenAI-compatible API (OpenAI, LM Studio, Ollama, …)
    case openai
    #endif

    /// The appropiate default provider.
    ///
    /// Prefers Apple when Foundation Models are available,
    /// follows with Anthropic when a networking stack is present,
    /// and falls back to the mock test double when all fails.
    static var preferred: Self {
        #if canImport(FoundationModels)
        .apple
        #elseif canImport(Darwin) || canImport(FoundationNetworking)
        .anthropic
        #else
        .mock
        #endif
    }
}

/// Shared endpoint options for hosted or OpenAI-compatible Playground providers.
///
/// Add `@OptionGroup var providerOptions: ProviderEndpointOptions` to commands
/// that expose configurable remote providers.
struct ProviderEndpointOptions: ParsableArguments {
    @Option(
        name: .customLong("model"),
        help: "Model identifier for providers that support model selection.",
    )
    var modelString: String?

    @Option(
        name: .customLong("base-url"),
        help: "API base URL for providers that support custom endpoints.",
    )
    var baseURLString: String?

    @Flag(
        name: .customLong("skip-credential"),
        help: "Skip provider authentication headers for local compatible servers.",
    )
    var skipCredentialFlag = false

    var baseURL: URL? {
        baseURLString.flatMap { URL(string: $0) }
    }

    var model: String? {
        modelString
    }

    var skipCredential: Bool {
        skipCredentialFlag
    }

    var configuration: ProviderEndpointConfiguration {
        ProviderEndpointConfiguration(
            baseURL: baseURL,
            model: model,
            skipCredential: skipCredential,
        )
    }

    mutating func validate() throws {
        if let raw = baseURLString, URL(string: raw) == nil {
            throw ValidationError("'\(raw)' is not a valid URL for --base-url.")
        }
        if skipCredential, baseURLString == nil {
            throw ValidationError("--skip-credential requires --base-url.")
        }
    }
}

/// Provider-agnostic endpoint settings applied by providers that support them.
struct ProviderEndpointConfiguration: Sendable {
    /// Override API endpoint base URL.
    var baseURL: URL?
    /// Override provider model identifier.
    var model: String?
    /// Whether to omit provider authentication headers.
    var skipCredential: Bool

    /// Default provider endpoint configuration.
    static let `default` = Self(baseURL: nil, model: nil, skipCredential: false)

    /// Resolves the configured model or a provider-specific default.
    func model(default defaultModel: String) -> String {
        model ?? defaultModel
    }
}
