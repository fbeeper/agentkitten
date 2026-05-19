// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Default behavioral configuration for tool use within an ``Agent``.
///
/// `ToolBehavior` captures how tools are used at runtime: the turn-scoped
/// step budget, the default tool availability, and prompt-engineering
/// guidance applied when tools are present.
///
/// Structural concerns — which tools exist and how calls are approved — live
/// in ``ToolDefinition``. Inference concerns — temperature and token limits
/// — live in ``InferenceConfiguration``.
public struct ToolBehavior: Sendable {
    /// Turn-scoped budget for model-requested tool execution.
    ///
    /// Default: `.budget(20)`.
    public let defaultStepBudget: ToolStepBudget
    /// Tool availability applied by default for direct execution turns.
    public let defaultSelection: ToolSelection
    /// Prompt guidance injected into the system prompt when tools are available.
    public let guidancePrompt: String
    /// Schema description for the injected rationale field.
    public let rationaleSchemaDescription: String
    /// Reason string returned when tools are fully disabled.
    public let disabledReason: String
    /// Format string for the reason returned when a specific tool is unavailable; takes one `%@` for the tool name.
    public let unavailableReasonFormat: String

    /// Creates tool behavior configuration.
    ///
    /// - Parameters:
    ///   - defaultStepBudget: Turn-scoped tool execution limit. Defaults to `.budget(20)`.
    ///   - defaultSelection: Tool availability for direct execution turns. Defaults to `.all`.
    ///   - guidancePrompt: Prompt guidance injected when tools are available. Defaults to ``defaultGuidancePrompt``.
    ///   - rationaleSchemaDescription: Schema description for the injected rationale field.
    ///   - disabledReason: Reason string returned when tools are fully disabled.
    ///   - unavailableReasonFormat: Format string for the reason when a specific tool is unavailable.
    public init(
        defaultStepBudget: ToolStepBudget = .budget(20),
        defaultSelection: ToolSelection = .all,
        guidancePrompt: String = Self.defaultGuidancePrompt,
        rationaleSchemaDescription: String = ToolRationale.schemaDescription,
        disabledReason: String = Self.defaultDisabledReason,
        unavailableReasonFormat: String = Self.defaultUnavailableReasonFormat,
    ) {
        self.defaultStepBudget = defaultStepBudget
        self.defaultSelection = defaultSelection
        self.guidancePrompt = guidancePrompt
        self.rationaleSchemaDescription = rationaleSchemaDescription
        self.disabledReason = disabledReason
        self.unavailableReasonFormat = unavailableReasonFormat
    }
}

extension ToolBehavior {
    /// Default prompt guidance injected when tools are available.
    public static let defaultGuidancePrompt =
        """
        When tools are available, use them only when needed. A denied or failed tool call \
        can be a normal constraint, not necessarily a terminal failure. Do not stop solely \
        because a tool failed or was denied. Continue the current task using other available \
        tools or reasoning if possible, and report that you cannot proceed only when the \
        unavailable tool was essential. Do not infer permanent tool unavailability from an \
        earlier denied approval, and do not check whether a tool is available by calling it \
        speculatively. When calling any tool, always supply a concise \
        `\(ToolRationale.schemaKey)` value — one action-oriented phrase stating what the \
        tool will do, not why the user asked.
        """

    /// Default reason string returned when tools are fully disabled.
    public static let defaultDisabledReason: String = "tools disabled"
    /// Default format string for the reason when a specific tool is unavailable.
    public static let defaultUnavailableReasonFormat = "tool unavailable: %@"
}

extension ToolBehavior {
    package var runtimeConfig: ToolRuntimeConfig {
        ToolRuntimeConfig(
            rationaleSchemaDescription: rationaleSchemaDescription,
            disabledReason: disabledReason,
            unavailableReasonFormat: unavailableReasonFormat,
        )
    }
}
