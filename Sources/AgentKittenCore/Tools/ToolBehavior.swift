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
    /// Prompt guidance policy for generic tool use.
    public enum Guidance: Sendable, Equatable {
        /// Use AgentKitten's default tool guidance.
        case `default`
        /// Use the provided custom tool guidance text.
        case custom(String)

        static var defaultPrompt: String {
            AgentKittenLocalization.string("tools.guidancePrompt")
        }

        var prompt: String {
            switch self {
            case .default:
                Self.defaultPrompt
            case .custom(let prompt):
                prompt
            }
        }
    }

    /// Schema description policy for the injected rationale field.
    public enum RationaleGuidance: Sendable, Equatable {
        /// Use AgentKitten's default rationale field description.
        case `default`
        /// Use the provided custom description for the rationale schema field.
        case custom(String)

        var schemaDescription: String {
            switch self {
            case .default:
                ToolRationale.schemaDescription
            case .custom(let description):
                description
            }
        }
    }

    /// Turn-scoped budget for model-requested tool execution.
    ///
    /// Default: `.budget(20)`.
    public let defaultStepBudget: ToolStepBudget
    /// Tool availability applied by default for direct execution turns.
    public let defaultSelection: ToolSelection
    /// Prompt guidance policy applied when tools are available.
    public let guidance: Guidance
    /// Schema description policy for the injected rationale field.
    public let rationaleGuidance: RationaleGuidance

    /// Creates tool behavior configuration.
    ///
    /// - Parameters:
    ///   - defaultStepBudget: Turn-scoped tool execution limit. Defaults to `.budget(20)`.
    ///   - defaultSelection: Tool availability for direct execution turns. Defaults to `.all`.
    ///   - guidance: Prompt guidance policy applied when tools are available. Defaults to `.default`.
    ///   - rationaleGuidance: Schema description policy for the injected rationale field. Defaults to `.default`.
    public init(
        defaultStepBudget: ToolStepBudget = .budget(20),
        defaultSelection: ToolSelection = .all,
        guidance: Guidance = .default,
        rationaleGuidance: RationaleGuidance = .default,
    ) {
        self.defaultStepBudget = defaultStepBudget
        self.defaultSelection = defaultSelection
        self.guidance = guidance
        self.rationaleGuidance = rationaleGuidance
    }
}
