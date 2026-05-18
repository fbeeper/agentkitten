// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Abstraction over LLM providers.
///
/// Conforming types power the inference step of the agent loop. Implement
/// ``makeSession(systemPrompt:toolRuntime:)`` to return a per-conversation
/// session that handles both individual turns and typed structured output.
///
/// Tool execution dependencies are bundled in the ``ToolRuntime`` passed at
/// session creation. Provider sessions bridge tools from that runtime and
/// invoke pending calls through its coordinated execution path.
///
/// **Invariants conformers must satisfy:**
/// - **Thread safety:** conforming types must be `Sendable` and safe to call
///   from any isolation domain.
public protocol InferenceProviding: Sendable {
    /// The concrete session type.
    associatedtype Session: InferenceSession & StructuredInferenceSession

    /// Performs provider-specific compatibility checks before a conversation session
    /// is constructed.
    ///
    /// Use this for constraints derivable from provider metadata plus the registered
    /// tools and current tool selection, such as supported tool-result content kinds.
    nonisolated func preflight(
        toolRegistry: ToolRegistry,
        toolSelection: ToolSelection,
    ) throws

    /// Returns whether a conversation can be reused across a turn-configuration transition.
    nonisolated func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility

    /// Creates a new session for a single conversation thread.
    ///
    /// - Parameters:
    ///   - systemPrompt: Instructions that define the agent's role, or `nil` for none.
    ///   - toolRuntime: Exposes bridged tools, turn lifecycle, approval coordination,
    ///     and the provider-facing invocation path.
    ///   - toolSelection: Tool availability for this session. Providers that bind tools at
    ///     session-construction time (e.g. Apple) use this to decide whether to bridge tools;
    ///     providers that bind per-request (e.g. Anthropic) may ignore it.
    ///   - inferenceContext: Custom inference-domain values for this session. Providers that
    ///     bind model identity at construction time (e.g. Apple) read their key here; providers
    ///     that apply model identity per-request (e.g. Anthropic) may ignore it.
    /// - Returns: A fresh provider session that will handle all turns
    ///   within one ``Conversation``.
    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> Session

    /// Creates a new session that continues from an existing one, rebinding to a new tool set.
    ///
    /// Called when ``SessionCompatibility/rebuildSession`` is returned for a turn-configuration
    /// transition. The new session should preserve as much conversation context as the provider
    /// supports (e.g. Apple uses the prior session's trace; Anthropic copies stored history).
    ///
    /// Only providers that return ``SessionCompatibility/rebuildSession`` from
    /// ``sessionCompatibility(from:to:)`` need to implement this method. The default
    /// implementation discards the prior session and delegates to
    /// ``makeSession(systemPrompt:toolRuntime:toolSelection:inferenceContext:)``; it exists as a
    /// safe fallback but loses conversation state, so only opt into `.rebuildSession` if you
    /// implement real continuation here.
    ///
    /// - Parameters:
    ///   - session: The existing session whose context should be preserved.
    ///   - systemPrompt: Instructions that define the agent's role, or `nil` for none.
    ///   - toolRuntime: The new tool runtime for the rebuilt session.
    ///   - toolSelection: Tool availability for the rebuilt session.
    ///   - inferenceContext: Custom inference-domain values for the rebuilt session.
    /// - Returns: A fresh session that continues from `session`.
    func makeSession(
        continuing session: Session,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws -> Session
}

extension InferenceProviding {
    public nonisolated func preflight(
        toolRegistry: ToolRegistry,
        toolSelection: ToolSelection,
    ) throws {}

    public nonisolated func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility {
        if current.provider != next.provider || current.toolSelection != next.toolSelection {
            return .replace
        }
        return .reuse
    }

    public func makeSession(
        continuing session: Session,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws -> Session {
        makeSession(
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            inferenceContext: inferenceContext,
        )
    }
}

/// Describes whether an existing conversation can be reused across a
/// turn-configuration transition.
public enum SessionCompatibility: Sendable {
    /// Reuse the existing conversation session.
    case reuse
    /// Keep the existing conversation but rebuild its provider session.
    ///
    /// The conversation's identity (``Conversation/sessionId``) and prior history are
    /// preserved. Only the inner provider session is replaced, rebinding to the new
    /// tool set. Use this when something in the configuration changes that the provider
    /// cannot adapt to mid-session (e.g. a tool-availability change on Apple's
    /// on-device `LanguageModelSession`).
    case rebuildSession
    /// Discard the existing conversation and create a fresh one.
    case replace
}

/// A lightweight wrapper around a concrete inference provider.
///
/// Keeps the provider's concrete session types intact while offering a common
/// entry point and convenience factories for standard providers:
///
/// ```swift
/// let provider = InferenceProvider.apple()  // on-device, macOS 26+
/// let provider = InferenceProvider.mock()   // canned responses for tests
/// ```
public struct InferenceProvider<Provider: InferenceProviding>: InferenceProviding {
    /// The concrete session type, forwarded from the wrapped provider.
    public typealias Session = Provider.Session

    private let provider: Provider

    /// Creates a wrapper for a concrete provider.
    public init(_ provider: Provider) {
        self.provider = provider
    }

    /// Creates a new session for a single conversation thread.
    public func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext = .empty,
    ) -> Provider.Session {
        provider.makeSession(
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            inferenceContext: inferenceContext,
        )
    }

    /// Performs provider-specific compatibility checks before session construction.
    public func preflight(
        toolRegistry: ToolRegistry,
        toolSelection: ToolSelection,
    ) throws {
        try provider.preflight(
            toolRegistry: toolRegistry,
            toolSelection: toolSelection,
        )
    }

    /// Returns whether a conversation can be reused across a turn-configuration transition.
    public func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility {
        provider.sessionCompatibility(from: current, to: next)
    }

    /// Creates a new session that continues from an existing one, rebinding to a new tool set.
    public func makeSession(
        continuing session: Provider.Session,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws -> Provider.Session {
        try await provider.makeSession(
            continuing: session,
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            inferenceContext: inferenceContext,
        )
    }
}

extension InferenceProvider where Provider == MockInferenceProvider {
    /// A mock provider that returns canned responses.
    ///
    /// Useful in tests, previews, and platforms where on-device models are unavailable.
    public static func mock() -> Self {
        Self(MockInferenceProvider())
    }
}
