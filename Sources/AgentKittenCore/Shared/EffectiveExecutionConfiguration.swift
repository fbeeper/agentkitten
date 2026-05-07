// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

public struct EffectiveExecutionConfiguration: Sendable, Equatable, Hashable {
    /// Tool availability for this execution.
    public let toolSelection: ToolSelection
    /// Turn-scoped budget for model-requested tool execution.
    public let toolStepBudget: ToolStepBudget
    /// The fully resolved inference configuration used for this execution.
    public let inferenceConfiguration: InferenceConfiguration
    /// The resolved provider reference used for this execution.
    public let provider: ProviderReference
    /// Custom values in the ``ExecutionConfigurationDomain/inference`` domain.
    ///
    /// Stored as an ``InferenceContext`` so providers can use the typed subscript
    /// in ``InferenceProviding/sessionCompatibility(from:to:)`` and so that a
    /// change in these values triggers the appropriate session reuse or rebuild
    /// decision via ``EffectiveExecutionConfiguration``'s `Equatable` conformance.
    public let inferenceContext: InferenceContext

    public init(
        toolSelection: ToolSelection = .all,
        toolStepBudget: ToolStepBudget = .budget(20),
        inferenceConfiguration: InferenceConfiguration = .init(),
        provider: ProviderReference = .default,
        inferenceContext: InferenceContext = .empty
    ) {
        self.toolSelection = toolSelection
        self.toolStepBudget = toolStepBudget
        self.inferenceConfiguration = inferenceConfiguration
        self.provider = provider
        self.inferenceContext = inferenceContext
    }

    init(environment: ExecutionEnvironment) {
        self.init(
            toolSelection: environment.toolSelection,
            toolStepBudget: environment.toolStepBudget,
            inferenceConfiguration: environment.inferenceConfiguration,
            provider: environment.provider,
            inferenceContext: InferenceContext(customValues: environment.customValues(for: .inference))
        )
    }

    func inferenceRequestParameters(
        toolExecutionContext: ToolExecutionContext = .empty
    ) -> InferenceRequestParameters {
        InferenceRequestParameters(
            configuration: inferenceConfiguration,
            toolStepBudget: toolStepBudget,
            toolSelection: toolSelection,
            toolExecutionContext: toolExecutionContext,
            inferenceContext: inferenceContext
        )
    }
}
