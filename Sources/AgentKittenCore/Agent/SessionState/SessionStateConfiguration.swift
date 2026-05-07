// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Configuration for surfacing session-state scratchpad tools to the model.
///
/// When enabled on an ``Agent``, AgentKitten injects built-in state tools into each
/// session and appends prompt guidance describing the intended use of ephemeral,
/// session-scoped state.
public struct SessionStateConfiguration: Sendable, Equatable {
    /// Default prompt guidance appended when session-state tooling is enabled.
    public static var defaultPromptGuidance: String {
        AgentKittenLocalization.string("sessionState.defaultPromptGuidance")
    }

    /// Additional guidance appended when session state is exposed in read-only mode.
    static var readOnlyPromptGuidance: String {
        AgentKittenLocalization.string("sessionState.readOnlyPromptGuidance")
    }

    /// Prompt guidance appended when session-state tooling is enabled.
    public let promptGuidance: String

    /// Creates a session-state tool configuration.
    ///
    /// - Parameter promptGuidance: Prompt guidance to append. Defaults to
    ///   ``defaultPromptGuidance``. Pass an empty string to suppress the
    ///   additional guidance entirely.
    public init(promptGuidance: String = Self.defaultPromptGuidance) {
        self.promptGuidance = promptGuidance
    }
}

/// Whether an ``Agent`` should expose session-state tooling.
public enum SessionStateMode: Sendable, Equatable {
    /// Do not expose built-in session-state tools.
    case disabled
    /// Expose read-only built-in session-state tools using the given configuration.
    case readOnly(SessionStateConfiguration)
    /// Expose built-in session-state tools using the given configuration.
    case enabled(SessionStateConfiguration)

    /// Expose read-only built-in session-state tools using AgentKitten's default guidance.
    public static let readOnlyWithDefaultGuidance = Self.readOnly(.init())

    /// Expose built-in session-state tools using AgentKitten's default guidance.
    public static let enabledWithDefaultGuidance = Self.enabled(.init())
}
