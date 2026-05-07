// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

// MARK: - Top-level trace snapshot types

/// AgentTrace-owned snapshot of a ``ProviderReference`` value.
public enum ProviderReferenceSnapshot: Sendable, Codable, Equatable, Hashable {
    /// The agent's default provider.
    case `default`
    /// A named provider type, identified by its Swift type name.
    case named(String)

    private enum CodingKeys: String, CodingKey { case type, name }
    private enum CaseKind: String, Codable { case `default`, named }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CaseKind.self, forKey: .type) {
        case .default:
            self = .default
        case .named:
            self = .named(try container.decode(String.self, forKey: .name))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .default:
            try container.encode(CaseKind.default, forKey: .type)
        case .named(let name):
            try container.encode(CaseKind.named, forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}

/// AgentTrace-owned snapshot of a ``ToolSelection`` value.
public enum ToolSelectionSnapshot: Sendable, Codable, Equatable, Hashable {
    case all
    case disabled
    case including([String])
    case excluding([String])

    private enum CodingKeys: String, CodingKey { case type, names }
    private enum CaseKind: String, Codable { case all, disabled, including, excluding }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CaseKind.self, forKey: .type) {
        case .all:
            self = .all
        case .disabled:
            self = .disabled
        case .including:
            self = .including(try container.decode([String].self, forKey: .names))
        case .excluding:
            self = .excluding(try container.decode([String].self, forKey: .names))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try container.encode(CaseKind.all, forKey: .type)
        case .disabled:
            try container.encode(CaseKind.disabled, forKey: .type)
        case .including(let names):
            try container.encode(CaseKind.including, forKey: .type)
            try container.encode(names, forKey: .names)
        case .excluding(let names):
            try container.encode(CaseKind.excluding, forKey: .type)
            try container.encode(names, forKey: .names)
        }
    }
}

/// AgentTrace-owned snapshot of a ``ToolStepBudget`` value.
public enum ToolStepBudgetSnapshot: Sendable, Codable, Equatable, Hashable {
    case disabled
    case budget(UInt)
    case unbounded

    private enum CodingKeys: String, CodingKey { case type, budget }
    private enum CaseKind: String, Codable { case disabled, budget, unbounded }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CaseKind.self, forKey: .type) {
        case .disabled:
            self = .disabled
        case .budget:
            self = .budget(try container.decode(UInt.self, forKey: .budget))
        case .unbounded:
            self = .unbounded
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .disabled:
            try container.encode(CaseKind.disabled, forKey: .type)
        case .budget(let value):
            try container.encode(CaseKind.budget, forKey: .type)
            try container.encode(value, forKey: .budget)
        case .unbounded:
            try container.encode(CaseKind.unbounded, forKey: .type)
        }
    }
}

/// AgentTrace-owned snapshot of an ``InferenceConfiguration`` value.
public struct InferenceConfigurationSnapshot: Sendable, Codable, Equatable, Hashable {
    /// Sampling temperature at the time of the turn.
    public let temperature: Double
    /// Maximum token budget at the time of the turn.
    public let maxTokens: Int
}

/// AgentTrace-owned snapshot of trace-safe custom execution-context values.
public struct CustomContextSnapshot: Sendable, Codable, Equatable, Hashable {
    /// One custom context entry.
    public struct Entry: Sendable, Codable, Equatable, Hashable {
        /// Stable execution-configuration key identifier.
        public let key: String
        /// Trace-safe string summary of the stored value.
        public let valueSummary: String
    }

    /// Sorted trace-safe custom context entries.
    public let entries: [Entry]
}

/// AgentTrace-owned snapshot of a conversation resolution outcome (reuse / rebuildSession / replace).
public enum ConversationResolutionSnapshot: String, Sendable, Codable, Equatable, Hashable {
    /// Both the conversation lane and inference session were reused unchanged.
    case reuse
    /// The conversation lane was reused but the inference session was rebuilt.
    case rebuildSession
    /// Both the conversation lane and inference session were replaced.
    case replace
}

/// AgentTrace-owned snapshot of a resolved conversation's runtime identity.
public struct ConversationIdentitySnapshot: Sendable, Codable, Equatable, Hashable {
    /// Stable conversation lane identifier.
    public let conversationID: String
    /// Current underlying inference session identifier.
    public let inferenceSessionID: String
}

/// AgentTrace-owned snapshot of per-turn overrides supplied via ``TurnOverrides``.
public struct TurnOverridesSnapshot: Sendable, Codable, Equatable, Hashable {
    /// Per-turn tool selection override, if set.
    public let toolSelection: ToolSelectionSnapshot?
    /// Per-turn tool step budget override, if set.
    public let toolStepBudget: ToolStepBudgetSnapshot?
    /// Per-turn inference configuration override, if set.
    public let inferenceConfiguration: InferenceConfigurationSnapshot?
    /// Per-turn provider override, if set.
    public let provider: ProviderReferenceSnapshot?
}

// MARK: - AgentTrace entry types

extension AgentTraceEntry.Kind {
    /// Compact execution preparation record for one turn.
    public struct ExecutionPreparationInfo: Sendable, Codable, Equatable, Hashable {
        /// Compatibility verdict.
        public let verdict: ConversationResolutionSnapshot
        /// Provider used for this turn.
        public let provider: ProviderReferenceSnapshot
        /// Tool selection in effect for this turn.
        public let toolSelection: ToolSelectionSnapshot
        /// Tool step budget in effect for this turn.
        public let toolStepBudget: ToolStepBudgetSnapshot
        /// Inference configuration in effect for this turn.
        public let inferenceConfiguration: InferenceConfigurationSnapshot
        /// Custom inference-context values in effect for this turn.
        public let inferenceContext: CustomContextSnapshot?
        /// Per-turn overrides applied on top of agent defaults, if any.
        public let turnOverrides: TurnOverridesSnapshot?
    }

    /// Resolved conversation identity for one turn.
    public struct ConversationResolvedInfo: Sendable, Codable, Equatable, Hashable {
        /// Resolved conversation identity.
        public let identity: ConversationIdentitySnapshot
        /// How the conversation and inference session were resolved for this turn.
        public let resolutionKind: ConversationResolutionSnapshot
    }
}

// MARK: - Framework type → snapshot conversions

extension ConversationProvider.ConversationResolutionResult.Kind {
    var traceSnapshot: ConversationResolutionSnapshot {
        switch self {
        case .reuse:
            .reuse
        case .rebuildSession:
            .rebuildSession
        case .replace:
            .replace
        }
    }
}

extension ConversationIdentity {
    var traceSnapshot: ConversationIdentitySnapshot {
        ConversationIdentitySnapshot(
            conversationID: conversationID.description,
            inferenceSessionID: inferenceSessionID.description
        )
    }
}

extension ProviderReference {
    var traceSnapshot: ProviderReferenceSnapshot {
        if let name = providerTypeName {
            .named(name)
        } else {
            .default
        }
    }
}

extension ToolSelection {
    var traceSnapshot: ToolSelectionSnapshot {
        switch self {
        case .all:
            .all
        case .disabled:
            .disabled
        case .including(let names):
            .including(names.sorted())
        case .excluding(let names):
            .excluding(names.sorted())
        }
    }
}

extension ToolStepBudget {
    var traceSnapshot: ToolStepBudgetSnapshot {
        switch self {
        case .disabled:
            .disabled
        case .budget(let value):
            .budget(value)
        case .unbounded:
            .unbounded
        }
    }
}

extension InferenceConfiguration {
    var traceSnapshot: InferenceConfigurationSnapshot {
        InferenceConfigurationSnapshot(temperature: temperature, maxTokens: maxTokens)
    }
}

extension TurnOverrides {
    var traceSnapshot: TurnOverridesSnapshot? {
        guard toolSelection != nil || toolStepBudget != nil || inferenceConfiguration != nil || provider != nil else {
            return nil
        }
        return TurnOverridesSnapshot(
            toolSelection: toolSelection.map(\.traceSnapshot),
            toolStepBudget: toolStepBudget.map(\.traceSnapshot),
            inferenceConfiguration: inferenceConfiguration.map(\.traceSnapshot),
            provider: provider.map(\.traceSnapshot)
        )
    }
}
