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

/// OpenAI-specific CLI options shared across Playground commands.
///
/// Add `@OptionGroup var openAIOptions: OpenAIProviderOptions` to any command that
/// exposes `--provider openai`. Pass `--openai-base-url` to target LM Studio or another
/// local server. Pass `--openai-model` to override the default model identifier.
struct OpenAIProviderOptions: ParsableArguments {
    @Option(
        name: .customLong("openai-model"),
        help: "Model identifier for --provider openai (or local model name for LM Studio).",
    )
    var model: String = "gpt-4o"

    @Option(
        name: .customLong("openai-base-url"),
        help: "API base URL for --provider openai. Use to point at LM Studio or another local server.",
    )
    var baseURLString: String?

    var baseURL: URL? {
        baseURLString.flatMap { URL(string: $0) }
    }
}
