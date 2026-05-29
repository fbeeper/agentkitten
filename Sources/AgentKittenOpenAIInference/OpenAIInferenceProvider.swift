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
/// This provider supports plain text chat, tool use, structured output, token
/// counting, and context compaction.
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

    /// The default structured-output instruction format string.
    ///
    /// Used when no custom `structuredOutputInstructionFormat` is supplied to the provider initializer.
    /// Receives one `%@` argument: the JSON schema string.
    public static let defaultStructuredOutputInstructionFormat = """
    Respond with a single valid JSON value that conforms to this schema:
    %@
    Output only the raw JSON value. Do not use markdown, code blocks, or backticks. \
    When the root schema is an object, start with { and end with }; \
    when it is an array, start with [ and end with ].
    """

    private let credentials: OpenAICredentials
    private let model: String
    private let baseURL: URL
    private let historyRenderingConfiguration: HistoryRenderingConfiguration
    private let structuredOutputInstructionFormat: String

    /// Creates an OpenAI-compatible provider.
    ///
    /// - Parameters:
    ///   - credentials: The credential source. Defaults to reading `OPENAI_API_KEY`
    ///     from the process environment.
    ///   - model: The model identifier. Defaults to `"gpt-4o"`.
    ///   - baseURL: The API base URL. Defaults to `https://api.openai.com/v1`.
    ///     Override to point at LM Studio, Ollama, or other local servers.
    ///   - historyRenderingConfiguration: Labels and format strings used when rendering history
    ///     during context compaction. Defaults to built-in English values.
    ///   - structuredOutputInstructionFormat: System-prompt instruction injected for structured
    ///     output requests. Must contain exactly one `%@` placeholder, which is replaced with
    ///     the JSON schema string at generation time. Passing a string with zero or more than
    ///     one `%@` triggers a precondition failure at init.
    public init(
        credentials: OpenAICredentials = .key(EnvironmentAPIKeyProvider("OPENAI_API_KEY")),
        model: String = "gpt-4o",
        baseURL: URL = OpenAIInferenceProvider.defaultBaseURL,
        historyRenderingConfiguration: HistoryRenderingConfiguration = HistoryRenderingConfiguration(),
        structuredOutputInstructionFormat: String = OpenAIInferenceProvider.defaultStructuredOutputInstructionFormat,
    ) {
        precondition(
            structuredOutputInstructionFormat.formatPlaceholderCount == 1,
            "structuredOutputInstructionFormat must contain exactly one %@ placeholder for the JSON schema string.",
        )
        self.credentials = credentials
        self.model = model
        self.baseURL = baseURL
        self.historyRenderingConfiguration = historyRenderingConfiguration
        self.structuredOutputInstructionFormat = structuredOutputInstructionFormat
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
            historyRenderingConfiguration: historyRenderingConfiguration,
            structuredOutputInstructionFormat: structuredOutputInstructionFormat,
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
