// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import ArgumentParser

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
