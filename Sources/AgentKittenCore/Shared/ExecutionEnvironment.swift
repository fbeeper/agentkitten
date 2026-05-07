// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

protocol ExecutionEnvironmentKey {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
}

struct ExecutionEnvironment: Sendable {
    private var storage: [ObjectIdentifier: any Sendable] = [:]
    private var customValues: [String: ExecutionConfigurationCustomValue] = [:]

    subscript<Key: ExecutionEnvironmentKey>(_ key: Key.Type) -> Key.Value {
        get {
            storage[ObjectIdentifier(key)] as? Key.Value ?? key.defaultValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }

    func overlaying(_ overlay: Self) -> Self {
        var result = self
        for (key, value) in overlay.storage {
            result.storage[key] = value
        }
        for (key, value) in overlay.customValues {
            result.customValues[key] = value
        }
        return result
    }

    func overlaying(_ turnOverrides: TurnOverrides) -> Self {
        overlaying(Self(turnOverrides: turnOverrides))
    }

    func customValues(for domain: ExecutionConfigurationDomain) -> [String: ExecutionConfigurationCustomValue] {
        customValues.filter { $0.value.domains.contains(domain) }
    }
}

extension ExecutionEnvironment {
    private enum ToolSelectionKey: ExecutionEnvironmentKey {
        static let defaultValue: ToolSelection = .all
    }

    private enum ToolStepBudgetKey: ExecutionEnvironmentKey {
        static let defaultValue: ToolStepBudget = .budget(20)
    }

    private enum InferenceConfigurationKey: ExecutionEnvironmentKey {
        static let defaultValue: InferenceConfiguration = .init()
    }

    private enum ProviderKey: ExecutionEnvironmentKey {
        static let defaultValue: ProviderReference = .default
    }

    init(behavior: AgentBehavior, toolBehavior: ToolBehavior) {
        self[ToolSelectionKey.self] = toolBehavior.defaultSelection
        self[ToolStepBudgetKey.self] = toolBehavior.defaultStepBudget
        self[InferenceConfigurationKey.self] = behavior.phaseBehaviors.base.inferenceConfiguration
        self[ProviderKey.self] = behavior.phaseBehaviors.base.provider
        self.customValues = behavior.phaseBehaviors.base.storedCustomValues
    }

    init(turnOverrides: TurnOverrides) {
        if let toolSelection = turnOverrides.toolSelection {
            self.toolSelection = toolSelection
        }
        if let toolStepBudget = turnOverrides.toolStepBudget {
            self.toolStepBudget = toolStepBudget
        }
        if let inferenceConfiguration = turnOverrides.inferenceConfiguration {
            self.inferenceConfiguration = inferenceConfiguration
        }
        if let provider = turnOverrides.provider {
            self.provider = provider
        }
        self.customValues = turnOverrides.storedCustomValues
    }

    var toolSelection: ToolSelection {
        get { self[ToolSelectionKey.self] }
        set { self[ToolSelectionKey.self] = newValue }
    }

    var toolStepBudget: ToolStepBudget {
        get { self[ToolStepBudgetKey.self] }
        set { self[ToolStepBudgetKey.self] = newValue }
    }

    var inferenceConfiguration: InferenceConfiguration {
        get { self[InferenceConfigurationKey.self] }
        set { self[InferenceConfigurationKey.self] = newValue }
    }

    var provider: ProviderReference {
        get { self[ProviderKey.self] }
        set { self[ProviderKey.self] = newValue }
    }

    var inferenceContext: InferenceContext {
        InferenceContext(customValues: customValues.filter { $0.value.domains.contains(.inference) })
    }
}
