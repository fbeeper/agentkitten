// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

@Suite("Convenience Inits")
struct ConvenienceInitTests {
    @Test func agent_singleProviderInit_runsTurnSuccessfully() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [.success("Hello from convenience init.")]
        )
        let agent = Agent(
            agentId: "convenience-test",
            provider: provider,
            behavior: .test("You are a test agent."),
            owner: "test-user"
        )

        let session = agent.makeSession()
        #expect(session.agentID == agent.agentId)
        #expect(session.ownerID == "test-user")

        let turn = try await session.send("Hi")
        let events = try await collectEvents(from: turn)
        let completions = assistantCompletions(in: events)
        #expect(completions == ["Hello from convenience init."])
    }

    // MARK: - AgentBehavior convenience inits

    @Test func agentBehavior_inferenceConfigurationInit_setsBasePhase() {
        let config = InferenceConfiguration(temperature: 0.2, maxTokens: 1024)
        let behavior = AgentBehavior(systemPrompt: "Test", inferenceConfiguration: config)
        #expect(behavior.phaseBehaviors.base.inferenceConfiguration == config)
        #expect(behavior.phaseBehaviors.base.provider == .default)
        #expect(behavior.defaultAutomaticCompactionPolicy == .disabled)
    }

    @Test func agentBehavior_inferenceConfigurationInit_propagatesCompactionPolicy() {
        let config = InferenceConfiguration(temperature: 0.3, maxTokens: 512)
        let behavior = AgentBehavior(
            systemPrompt: "Test",
            inferenceConfiguration: config,
            defaultAutomaticCompactionPolicy: .enabled()
        )
        #expect(behavior.phaseBehaviors.base.inferenceConfiguration == config)
        #expect(behavior.defaultAutomaticCompactionPolicy == .enabled())
    }

    // MARK: - Agent systemPrompt convenience inits

    @Test func agent_systemPromptWithProvider_runsTurnSuccessfully() async throws {
        let provider = ScriptedInferenceProvider(responses: [.success("Response.")])
        let agent = Agent(
            agentId: "sp-provider",
            provider: provider,
            systemPrompt: "You are a test agent.",
            owner: "test-user"
        )

        #expect(agent.owner == "test-user")
        let events = try await collectEvents(from: try await agent.makeSession().send("Hi"))
        #expect(assistantCompletions(in: events) == ["Response."])
    }

    @Test func agent_systemPromptWithInferenceConfiguration_appliesConfig() async throws {
        let config = InferenceConfiguration(temperature: 0.1, maxTokens: 128)
        let provider = ScriptedInferenceProvider(responses: [.success("ok")])
        let agent = Agent(
            provider: provider,
            systemPrompt: "Test",
            inferenceConfiguration: config
        )

        let session = agent.makeSession()
        _ = try await collectEvents(from: try await session.send("Hi"))

        let trace = await session.trace.snapshot()
        let prepInfo = trace.compactMap { entry -> AgentTraceEntry.Kind.ExecutionPreparationInfo? in
            if case .executionPreparation(let info) = entry.kind {
                return info
            }
            return nil
        }.first
        #expect(prepInfo?.inferenceConfiguration.temperature == config.temperature)
        #expect(prepInfo?.inferenceConfiguration.maxTokens == config.maxTokens)
    }

    @Test func agent_systemPromptWithAutomaticCompactionPolicy_appliesPolicy() async throws {
        let provider = ScriptedInferenceProvider(responses: [.success("ok")])
        let agent = Agent(
            provider: provider,
            systemPrompt: "Test",
            defaultAutomaticCompactionPolicy: .enabled()
        )

        let session = agent.makeSession()
        #expect(await session.automaticCompactionPolicy == .enabled())
    }
}
