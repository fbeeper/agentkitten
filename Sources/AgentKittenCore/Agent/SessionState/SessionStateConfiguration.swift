// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Configuration for surfacing session-state scratchpad tools to the model.
///
/// When enabled on an ``Agent``, AgentKitten injects built-in state tools into each
/// session and appends prompt guidance describing the intended use of ephemeral,
/// session-scoped state.
public struct SessionStateConfiguration: Sendable, Equatable {
    /// Prompt guidance appended when session-state tooling is enabled.
    public let promptGuidance: String
    /// Description of the get-state tool.
    public let getStateDescription: String
    /// Description of the key parameter for the get-state tool.
    public let getStateKeyDescription: String
    /// Description of the list-state-keys tool.
    public let listStateKeysDescription: String
    /// Description of the set-state tool.
    public let setStateDescription: String
    /// Description of the key parameter for the set-state tool.
    public let setStateKeyDescription: String
    /// Description of the value parameter for the set-state tool.
    public let setStateValueDescription: String
    /// Description of the remove-state tool.
    public let removeStateDescription: String
    /// Description of the key parameter for the remove-state tool.
    public let removeStateKeyDescription: String

    /// Creates a session-state tool configuration.
    ///
    /// - Parameter promptGuidance: Prompt guidance to append. Defaults to
    ///   ``defaultPromptGuidance``. Pass an empty string to suppress the
    ///   additional guidance entirely.
    /// - Parameter getStateDescription: Description for the get-state tool.
    /// - Parameter getStateKeyDescription: Description for the get-state tool's key parameter.
    /// - Parameter listStateKeysDescription: Description for the list-state-keys tool.
    /// - Parameter setStateDescription: Description for the set-state tool.
    /// - Parameter setStateKeyDescription: Description for the set-state tool's key parameter.
    /// - Parameter setStateValueDescription: Description for the set-state tool's value parameter.
    /// - Parameter removeStateDescription: Description for the remove-state tool.
    /// - Parameter removeStateKeyDescription: Description for the remove-state tool's key parameter.
    public init(
        promptGuidance: String = Self.defaultPromptGuidance,
        getStateDescription: String = Self.defaultGetStateDescription,
        getStateKeyDescription: String = Self.defaultGetStateKeyDescription,
        listStateKeysDescription: String = Self.defaultListStateKeysDescription,
        setStateDescription: String = Self.defaultSetStateDescription,
        setStateKeyDescription: String = Self.defaultSetStateKeyDescription,
        setStateValueDescription: String = Self.defaultSetStateValueDescription,
        removeStateDescription: String = Self.defaultRemoveStateDescription,
        removeStateKeyDescription: String = Self.defaultRemoveStateKeyDescription,
    ) {
        self.promptGuidance = promptGuidance
        self.getStateDescription = getStateDescription
        self.getStateKeyDescription = getStateKeyDescription
        self.listStateKeysDescription = listStateKeysDescription
        self.setStateDescription = setStateDescription
        self.setStateKeyDescription = setStateKeyDescription
        self.setStateValueDescription = setStateValueDescription
        self.removeStateDescription = removeStateDescription
        self.removeStateKeyDescription = removeStateKeyDescription
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
    public static let readOnlyWithDefaultGuidance = Self.readOnly(SessionStateConfiguration())

    /// Expose built-in session-state tools using AgentKitten's default guidance.
    public static let enabledWithDefaultGuidance = Self.enabled(SessionStateConfiguration())
}

// MARK: - Defaults

extension SessionStateConfiguration {
    /// Default prompt guidance appended when session-state tooling is enabled.
    public static let defaultPromptGuidance =
        """
        Session state is an optional scratchpad for small facts worth reusing across turns or \
        execution steps. Use it only when a fact should be remembered or retrieved later. \
        Do not create generic bookkeeping entries, and do not store plan outlines, goal \
        restatements, or final answers unless the user explicitly asks for that. \
        Prefer the fewest state reads and writes needed.
        """
    /// Additional guidance appended when session state is exposed in read-only mode.
    static let readOnlyPromptGuidance =
        "Session state is read-only in this session. You may inspect it, but you cannot modify it."

    /// Default description for the get-state tool.
    public static let defaultGetStateDescription =
        """
        Reads a value from the session scratchpad by key. Use this to recover facts,
        intermediate results, or todo state saved earlier in the same session.
        Returns the stored string value.
        """
    /// Default description of the key parameter for the get-state tool.
    public static let defaultGetStateKeyDescription = "Scratchpad key to read."

    /// Default description for the list-state-keys tool.
    public static let defaultListStateKeysDescription =
        """
        Lists the keys currently available in the session scratchpad. \
        Use this when you need to inspect what state exists before reading specific keys.
        """

    /// Default description for the set-state tool.
    public static let defaultSetStateDescription =
        "Writes a string value into the session scratchpad under a key."
    /// Default description of the key parameter for the set-state tool.
    public static let defaultSetStateKeyDescription = "Scratchpad key to write."
    /// Default description of the value parameter for the set-state tool.
    public static let defaultSetStateValueDescription = "String value to store."

    /// Default description for the remove-state tool.
    public static let defaultRemoveStateDescription =
        """
        Removes a value from the session scratchpad by key. \
        Use this when scratchpad information is no longer needed or would become stale.
        """
    /// Default description of the key parameter for the remove-state tool.
    public static let defaultRemoveStateKeyDescription = "Scratchpad key to remove."
}
