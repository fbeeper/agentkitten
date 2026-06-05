// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Per-turn execution configuration request.
///
/// `TurnOverrides` is a partial override surface. Omitted properties keep
/// the value inherited from the current execution environment.
public struct TurnOverrides: Sendable {
    /// Optional override for tool availability on this turn.
    public let toolSelection: ToolSelection?
    /// Optional override for the tool step budget on this turn.
    ///
    /// Overrides ``ToolBehavior/defaultStepBudget`` for this turn only.
    public let toolStepBudget: ToolStepBudget?
    /// Optional override for the inference configuration used on this turn.
    public let inferenceConfiguration: InferenceConfiguration?
    /// Optional override for the provider selected on this turn.
    public let provider: ProviderReference?
    /// Optional note prepended to the user message for this turn only.
    ///
    /// Composed with the user message text in ``AgentSession`` before the
    /// message is sent to the model. Subsequent turns that omit this property
    /// send only the original user message.
    ///
    /// Unlike ``toolSelection``, ``toolStepBudget``, ``inferenceConfiguration``,
    /// and ``provider``, `turnNote` is intentionally not propagated into
    /// `ExecutionEnvironment` or ``EffectiveExecutionConfiguration``.
    /// `ConversationProvider` uses ``EffectiveExecutionConfiguration`` equality
    /// to decide whether to reuse, rebuild, or replace a provider session. Keeping
    /// `turnNote` out of that type ensures different notes on consecutive turns
    /// never trigger an unintended session rebuild.
    public let turnNote: String?
    private var customValues: [String: ExecutionConfigurationCustomValue]

    /// Creates a per-turn execution configuration request.
    public init(
        toolSelection: ToolSelection? = nil,
        toolStepBudget: ToolStepBudget? = nil,
        inferenceConfiguration: InferenceConfiguration? = nil,
        provider: ProviderReference? = nil,
        turnNote: String? = nil,
    ) {
        self.toolSelection = toolSelection
        self.toolStepBudget = toolStepBudget
        self.inferenceConfiguration = inferenceConfiguration
        self.provider = provider
        self.turnNote = turnNote
        customValues = [:]
    }

    /// Accesses a typed custom turn value.
    public subscript<Key: ExecutionConfigurationKey>(_ key: Key.Type) -> Key.Value? {
        get {
            customValues[Key.id]?.value as? Key.Value
        }
        set {
            if let newValue {
                customValues[Key.id] = ExecutionConfigurationCustomValue(
                    domains: Key.domains,
                    value: newValue,
                )
            } else {
                customValues.removeValue(forKey: Key.id)
            }
        }
    }
}

extension TurnOverrides {
    var storedCustomValues: [String: ExecutionConfigurationCustomValue] {
        customValues
    }
}

/// A domain that controls where a custom execution configuration value may be surfaced.
public struct ExecutionConfigurationDomain: Sendable, Equatable, Hashable {
    /// Custom values visible to tool execution policies.
    public static let toolApproval = Self(rawValue: "toolApproval")
    /// Custom values carried into ``InferenceContext`` for per-request reads by providers.
    ///
    /// Values in this domain also appear in
    /// ``EffectiveExecutionConfiguration/inferenceContext``, where they participate in
    /// session-compatibility decisions (e.g. triggering a session rebuild when the model
    /// selection changes).
    public static let inference = Self(rawValue: "inference")

    let rawValue: String
}

/// A typed key for storing custom values on ``TurnOverrides`` or ``AgentBehavior``.
public protocol ExecutionConfigurationKey {
    /// Value stored for this key.
    associatedtype Value: Sendable & Hashable

    /// Stable key identifier.
    static var id: String { get }

    /// Domains where this value may be surfaced.
    ///
    /// A key may declare multiple domains so a single value reaches multiple consumers
    /// (e.g. both ``ExecutionConfigurationDomain/inference`` and
    /// ``ExecutionConfigurationDomain/toolApproval``).
    ///
    /// Domain identifiers are intentionally not public. Library users must choose from
    /// domains defined by AgentKitten so projection boundaries remain explicit and auditable.
    static var domains: Set<ExecutionConfigurationDomain> { get }
}

extension ExecutionConfigurationKey {
    /// Default identifier based on the key type name.
    public static var id: String {
        String(describing: Self.self)
    }
}

/// A type-erased custom execution configuration value.
public struct ExecutionConfigurationCustomValue: Sendable {
    let domains: Set<ExecutionConfigurationDomain>
    let value: any Sendable & Hashable
}

extension ExecutionConfigurationCustomValue: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.domains == rhs.domains && AnyHashable(lhs.value) == AnyHashable(rhs.value)
    }
}

extension ExecutionConfigurationCustomValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(domains)
        hasher.combine(AnyHashable(value))
    }
}
