// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

/// An ``InferenceProviding`` conformer backed by Anthropic's Messages API.
///
/// Each ``Conversation`` gets its own ``AnthropicInferenceSession`` which
/// fetches an API key from the supplied ``APIKeyProviding`` at the start of
/// the first turn and caches it for the session's lifetime.
///
/// Use the ``InferenceProvider`` convenience factories instead of instantiating
/// this type directly:
///
/// ```swift
/// // Environment variable (CLI / Playground)
/// let provider = InferenceProvider.anthropic()
///
/// // Keychain (app)
/// let provider = InferenceProvider.anthropic(keychain: "com.example.App", account: "anthropic")
///
/// // Custom credentials
/// let provider = InferenceProvider.anthropic(credentials: MyVaultProvider())
/// ```
public actor AnthropicInferenceProvider: InferenceProviding {
    /// The default structured-output instruction format string.
    ///
    /// Used when no custom `structuredOutputInstructionFormat` is supplied to the provider initializer.
    /// Exposed so callers can build on or inspect the default without duplicating it.
    public static let defaultStructuredOutputInstructionFormat = """
    Respond with a single valid JSON value that conforms to this schema:
    %@
    Output only the raw JSON value. Do not use markdown, code blocks, or backticks. \
    When the root schema is an object, start with { and end with }; \
    when it is an array, start with [ and end with ].
    """

    private let credentials: any APIKeyProviding
    private let model: String
    private let historyRenderingConfiguration: HistoryRenderingConfiguration
    private let structuredOutputInstructionFormat: String

    /// Creates an Anthropic provider.
    ///
    /// - Parameters:
    ///   - credentials: The credential source. Defaults to reading `ANTHROPIC_API_KEY`
    ///     from the process environment.
    ///   - model: The Anthropic model identifier. Defaults to `"claude-sonnet-4-5"`.
    ///   - historyRenderingConfiguration: Labels and format strings used when rendering history
    ///     during context compaction. Defaults to built-in English values.
    ///   - structuredOutputInstructionFormat: System-prompt instruction injected for structured
    ///     output requests. Receives one `%@` argument: the JSON schema string.
    public init(
        credentials: any APIKeyProviding = EnvironmentAPIKeyProvider("ANTHROPIC_API_KEY"),
        model: String = "claude-sonnet-4-5",
        historyRenderingConfiguration: HistoryRenderingConfiguration = HistoryRenderingConfiguration(),
        structuredOutputInstructionFormat: String = AnthropicInferenceProvider.defaultStructuredOutputInstructionFormat,
    ) {
        self.credentials = credentials
        self.model = model
        self.historyRenderingConfiguration = historyRenderingConfiguration
        self.structuredOutputInstructionFormat = structuredOutputInstructionFormat
    }

    /// Returns whether a conversation can be reused across a turn-configuration transition.
    ///
    /// Anthropic applies tool availability at the API-request level on each turn, so
    /// a `toolSelection` change never requires rebuilding the session — the same history
    /// is re-posted with a different tool list on the next request.
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
    ///
    /// `toolSelection` is ignored here; Anthropic gates tools at the API-request level on
    /// each turn via ``InferenceConfiguration/toolsEnabled``.
    /// Model identity is also per-request: if ``AnthropicModelKey`` is set in
    /// `inferenceContext`, it overrides `model` on every turn for this session.
    public nonisolated func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> AnthropicInferenceSession {
        makeAnthropicSession(systemPrompt: systemPrompt, toolRuntime: toolRuntime)
    }

    private nonisolated func makeAnthropicSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        initialHistory: [AnthropicMessage] = [],
    ) -> AnthropicInferenceSession {
        AnthropicInferenceSession(
            credentials: credentials,
            defaultModel: model,
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            initialHistory: initialHistory,
            historyRenderingConfiguration: historyRenderingConfiguration,
            structuredOutputInstructionFormat: structuredOutputInstructionFormat,
        )
    }

    /// Creates a new session that continues from `session`, copying its stored history.
    ///
    /// Tools are rebound to the new ``ToolRuntime``. Prior conversation history is
    /// preserved so the model maintains context across the session rebuild.
    /// `toolSelection` is ignored; Anthropic gates tools per-request.
    public func makeSession(
        continuing session: AnthropicInferenceSession,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws -> AnthropicInferenceSession {
        let history = await session.captureHistory()
        return makeAnthropicSession(
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            initialHistory: history,
        )
    }

    // No combined compact+rebuild override: AnthropicInferenceSession conforms to
    // ContextCompactableSession and can compact its own mutable history in place,
    // so the protocol default (compact then rebuild as two separate steps) is sufficient.
}
