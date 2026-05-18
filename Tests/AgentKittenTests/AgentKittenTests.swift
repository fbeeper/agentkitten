// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import Testing

@Test func versionMatchesCore() {
    #expect(!AgentKitten.version.isEmpty)
}

@Test func directAgentTypesVisibleFromUmbrellaModule() {
    let behavior = AgentBehavior(systemPrompt: "Test")
    let toolBehavior = ToolBehavior()

    #expect(behavior.phaseBehaviors.base.inferenceConfiguration == .init())
    #expect(behavior.defaultAutomaticCompactionPolicy == AutomaticCompactionPolicy.disabled)
    #expect(toolBehavior.defaultSelection == .all)
    #expect(toolBehavior.guidance == .default)
    #expect(toolBehavior.defaultStepBudget == .budget(20))
}

@Test(.disabled("Disabled until the Swift Testing signal 10 issue is resolved"))
func agentSessionVisibleFromUmbrellaModule() {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: InferenceProvider.mock()),
        behavior: .init(systemPrompt: "Test"),
    )
    let session = agent.makeSession()

    #expect(session.ownerID == .local)
}
