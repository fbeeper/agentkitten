// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

// MARK: - Keys

private enum TestModelKey: ExecutionConfigurationKey {
    static let domains: Set<ExecutionConfigurationDomain> = [.inference]
    typealias Value = String
}

private enum TestApprovalKey: ExecutionConfigurationKey {
    static let domains: Set<ExecutionConfigurationDomain> = [.toolApproval]
    typealias Value = String
}

// MARK: - InferenceContext subscript

@Test func inferenceContext_subscript_roundTrips() {
    var context = InferenceContext()
    context[TestModelKey.self] = "opus"
    #expect(context[TestModelKey.self] == "opus")
}

@Test func inferenceContext_subscript_returnsNilWhenAbsent() {
    let context = InferenceContext()
    #expect(context[TestModelKey.self] == nil)
}

@Test func inferenceContext_subscript_removesValueOnNilAssignment() {
    var context = InferenceContext()
    context[TestModelKey.self] = "opus"
    context[TestModelKey.self] = nil
    #expect(context[TestModelKey.self] == nil)
}

// MARK: - EffectiveExecutionConfiguration equality with inferenceCustomValues

@Test func effectiveConfig_equalityChanges_whenInferenceValueDiffers() {
    var contextA = InferenceContext()
    contextA[TestModelKey.self] = "model-a"
    var contextB = InferenceContext()
    contextB[TestModelKey.self] = "model-b"

    let configA = EffectiveExecutionConfiguration(inferenceContext: contextA)
    let configB = EffectiveExecutionConfiguration(inferenceContext: contextB)
    #expect(configA != configB)
}

@Test func effectiveConfig_equalityPreserved_whenInferenceContextMatches() {
    var context = InferenceContext()
    context[TestModelKey.self] = "same-model"

    let configA = EffectiveExecutionConfiguration(inferenceContext: context)
    let configB = EffectiveExecutionConfiguration(inferenceContext: context)
    #expect(configA == configB)
}

// MARK: - ExecutionEnvironment derives inferenceContext from behavior and turn

@Test func executionEnvironment_behaviorValuesFlowToInferenceContext() {
    var phaseBehaviors = PhaseBehaviorSet()
    phaseBehaviors.base[TestModelKey.self] = "behavior-model"
    let behavior = AgentBehavior(systemPrompt: "Test", phaseBehaviors: phaseBehaviors)

    let environment = ExecutionEnvironment(behavior: behavior, toolBehavior: .init())
    let config = EffectiveExecutionConfiguration(environment: environment)

    #expect(config.inferenceContext[TestModelKey.self] == "behavior-model")
}

@Test func executionEnvironment_turnValueOverridesBehaviorValue() {
    var phaseBehaviors = PhaseBehaviorSet()
    phaseBehaviors.base[TestModelKey.self] = "behavior-model"
    let behavior = AgentBehavior(systemPrompt: "Test", phaseBehaviors: phaseBehaviors)

    var turn = TurnOverrides()
    turn[TestModelKey.self] = "turn-model"

    let environment = ExecutionEnvironment(behavior: behavior, toolBehavior: .init()).overlaying(turn)
    let config = EffectiveExecutionConfiguration(environment: environment)

    #expect(config.inferenceContext[TestModelKey.self] == "turn-model")
}

@Test func executionEnvironment_toolApprovalValuesDoNotAppearInInferenceContext() {
    var phaseBehaviors = PhaseBehaviorSet()
    phaseBehaviors.base[TestApprovalKey.self] = "approval-value"
    let behavior = AgentBehavior(systemPrompt: "Test", phaseBehaviors: phaseBehaviors)

    let environment = ExecutionEnvironment(behavior: behavior, toolBehavior: .init())
    let config = EffectiveExecutionConfiguration(environment: environment)

    #expect(config.inferenceContext[TestApprovalKey.self] == nil)
}

@Test func executionEnvironment_toolExecutionContextContainsOnlyToolApprovalValues() {
    var phaseBehaviors = PhaseBehaviorSet()
    phaseBehaviors.base[TestModelKey.self] = "behavior-model"
    phaseBehaviors.base[TestApprovalKey.self] = "approval-value"
    let behavior = AgentBehavior(systemPrompt: "Test", phaseBehaviors: phaseBehaviors)

    let environment = ExecutionEnvironment(behavior: behavior, toolBehavior: .init())
    let context = ToolExecutionContext(customValues: environment.customValues(for: .toolApproval))

    #expect(context[TestApprovalKey.self] == "approval-value")
    #expect(context[TestModelKey.self] == nil)
}

@Test func behaviorPhaseLookup_fallsBackToBasePhaseBehavior() {
    let base = PhaseBehavior(
        provider: .default,
        inferenceConfiguration: InferenceConfiguration(temperature: 0.3),
    )
    let phaseBehaviors = PhaseBehaviorSet(base: base)

    #expect(phaseBehaviors.behavior(for: .compaction).provider == base.provider)
    #expect(
        phaseBehaviors.behavior(for: .compaction).inferenceConfiguration
            == base.inferenceConfiguration,
    )
}
