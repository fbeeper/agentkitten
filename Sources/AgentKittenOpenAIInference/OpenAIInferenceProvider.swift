// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation

/// An ``InferenceProviding`` conformer backed by the OpenAI Chat Completions API.
///
/// Also compatible with any OpenAI-spec endpoint such as LM Studio, or other remote or
/// locally-hosted model servers. Configure `baseURL` to point at the running server.
///
/// Each ``Conversation`` gets its own ``OpenAIInferenceSession`` which fetches an API
/// key from the supplied ``APIKeyProviding`` at the start of each turn.
///
/// This provider supports plain text chat. It does not yet support tool use; if any
/// tool is selected, ``preflight(toolRegistry:toolSelection:)`` throws rather than
/// silently dropping the tools.
///
/// Use the ``InferenceProvider`` convenience factories instead of instantiating
/// this type directly:
///
/// ```swift
/// // OpenAI (environment variable)
/// let provider = InferenceProvider.openAI(model: "gpt-4o")
///
/// // LM Studio (local server, no key required)
/// let provider = InferenceProvider.lmStudio(
///     baseURL: URL(string: "http://localhost:1234/v1")!,
///     model: "qwen2.5-coder-7b-instruct"
/// )
///
/// // Custom credentials
/// let provider = InferenceProvider.openAI(credentials: MyVaultProvider(), model: "gpt-4o")
/// ```
public actor OpenAIInferenceProvider: InferenceProviding {
    /// The default OpenAI Chat Completions API base URL.
    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    private let credentials: OpenAICredentials
    private let model: String
    private let baseURL: URL

    /// Creates an OpenAI-compatible provider.
    ///
    /// - Parameters:
    ///   - credentials: The credential source. Defaults to reading `OPENAI_API_KEY`
    ///     from the process environment.
    ///   - model: The model identifier. Defaults to `"gpt-4o"`.
    ///   - baseURL: The API base URL. Defaults to `https://api.openai.com/v1`.
    ///     Override to point at LM Studio, Ollama, or other local servers.
    public init(
        credentials: OpenAICredentials = .key(EnvironmentAPIKeyProvider("OPENAI_API_KEY")),
        model: String = "gpt-4o",
        baseURL: URL = OpenAIInferenceProvider.defaultBaseURL,
    ) {
        self.credentials = credentials
        self.model = model
        self.baseURL = baseURL
    }

    /// Rejects configurations that select tools, which this text-only provider does not support.
    public nonisolated func preflight(
        toolRegistry: ToolRegistry,
        toolSelection: ToolSelection,
    ) throws {
        let selected = toolRegistry.all.filter { toolSelection.allows(toolName: $0.name) }
        guard selected.isEmpty else {
            throw InferenceError.unsupportedConfiguration(
                "OpenAIInferenceProvider does not yet support tool use; remove tools or disable them for this turn.",
            )
        }
    }

    /// Returns whether a conversation can be reused across a turn-configuration transition.
    ///
    /// OpenAI applies configuration at the API-request level on each turn, so only a
    /// provider change requires a fresh conversation.
    public nonisolated func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility {
        if current.provider != next.provider {
            return .replace
        }
        return .reuse
    }

    /// Creates a new session for a single conversation thread.
    public nonisolated func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection _: ToolSelection,
        inferenceContext _: InferenceContext,
    ) -> OpenAIInferenceSession {
        makeOpenAISession(systemPrompt: systemPrompt, toolRuntime: toolRuntime)
    }

    private nonisolated func makeOpenAISession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        initialHistory: [OpenAIMessage] = [],
    ) -> OpenAIInferenceSession {
        OpenAIInferenceSession(
            client: OpenAIHTTPClient(credentials: credentials, baseURL: baseURL),
            defaultModel: model,
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            initialHistory: initialHistory,
        )
    }

    /// Creates a new session that continues from `session`, copying its stored history.
    public func makeSession(
        continuing session: OpenAIInferenceSession,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection _: ToolSelection,
        inferenceContext _: InferenceContext,
    ) async throws -> OpenAIInferenceSession {
        let history = await session.captureHistory()
        return makeOpenAISession(
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            initialHistory: history,
        )
    }
}
#endif
