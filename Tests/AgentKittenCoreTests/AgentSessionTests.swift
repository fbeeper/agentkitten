// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

@Suite("Agent Session")
struct AgentSessionTests {
    @Test func makeSession_usesDefaultAndOverrideOwners() {
        let agent = Agent(
            agentId: "assistant",
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider()),
            behavior: .test(),
            owner: "default-user",
        )

        let defaultSession = agent.makeSession()
        let overrideSession = agent.makeSession(for: "override-user")

        #expect(defaultSession.agentID == agent.agentId)
        #expect(defaultSession.ownerID == "default-user")
        #expect(overrideSession.agentID == agent.agentId)
        #expect(overrideSession.ownerID == "override-user")
        #expect(defaultSession.sessionID != overrideSession.sessionID)
    }

    @Test func sessionsKeepTracesAndConversationReuseIndependent() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [
                .success("First response"),
                .success("Second response"),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let firstSession = agent.makeSession()
        let secondSession = agent.makeSession()

        let firstTurn = try await firstSession.send("first")
        _ = try await collectEvents(from: firstTurn)
        let secondTurn = try await secondSession.send("second")
        _ = try await collectEvents(from: secondTurn)

        let firstEntries = await firstSession.trace.snapshot()
        let secondEntries = await secondSession.trace.snapshot()

        #expect(await provider.script.executionSessionUseCount() == 2)
        #expect(firstEntries.allSatisfy { $0.invocationID == firstTurn.id })
        #expect(secondEntries.allSatisfy { $0.invocationID == secondTurn.id })
        #expect(!firstEntries.contains { $0.invocationID == secondTurn.id })
        #expect(!secondEntries.contains { $0.invocationID == firstTurn.id })
    }

    @Test func queuedSessionSerializesQueueWhileSecondSessionRunsIndependently() async throws {
        let provider = GateInferenceProvider()
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let firstSession = agent.makeQueuedSession()
        let secondSession = agent.makeQueuedSession()

        let firstTurn = await firstSession.send("a1")
        let firstTask = Task { try await collectEvents(from: firstTurn) }
        await provider.waitUntilStarted("a1")

        let queuedTurn = await firstSession.send("a2")
        let queuedTask = Task { try await collectEvents(from: queuedTurn) }

        let secondTurn = await secondSession.send("b1")
        let secondTask = Task { try await collectEvents(from: secondTurn) }
        await provider.waitUntilStarted("b1")

        #expect(await provider.hasStarted("a2") == false)

        await provider.release("b1")
        _ = try await secondTask.value
        #expect(await provider.hasStarted("a2") == false)

        await provider.release("a1")
        _ = try await firstTask.value
        await provider.waitUntilStarted("a2")

        await provider.release("a2")
        _ = try await queuedTask.value
    }

    @Test func invalidConversationConfigurationFailsBeforeSessionSend() async throws {
        let provider = InvalidConfigurationProvider()
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )

        do {
            _ = try await collectEvents(from: await agent.makeSession().send("hello"))
            Issue.record("Expected invalid conversation configuration to fail")
        } catch let error as InferenceError {
            guard case .unsupportedConfiguration(let message) = error else {
                Issue.record("Expected unsupportedConfiguration, got \(error)")
                return
            }
            #expect(message.contains("invalid test configuration"))
            #expect(await provider.sendCount() == 0)
        }
    }

    @Test func send_defaultPathUsesBehaviorDefaultInferenceConfiguration() async throws {
        let provider = ConfigurationRecordingProvider()
        let behavior = AgentBehavior(
            systemPrompt: "Test",
            phaseBehaviors: PhaseBehaviorSet(
                base: PhaseBehavior(
                    inferenceConfiguration: InferenceConfiguration(
                        temperature: 0.9,
                    ),
                ),
            ),
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: behavior,
        )

        _ = try await collectEvents(from: await agent.makeSession().send("hello"))

        #expect(
            await provider.recordedConfigurations() == [
                InferenceConfiguration(temperature: 0.9),
            ],
        )
    }

    @Test func send_explicitTurnOverridesUsesSuppliedInferenceConfiguration() async throws {
        let provider = ConfigurationRecordingProvider()
        let behavior = AgentBehavior(
            systemPrompt: "Test",
            phaseBehaviors: PhaseBehaviorSet(
                base: PhaseBehavior(
                    inferenceConfiguration: InferenceConfiguration(
                        temperature: 0.1,
                    ),
                ),
            ),
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: behavior,
        )
        let turnOverrides = TurnOverrides(
            inferenceConfiguration: InferenceConfiguration(
                temperature: 0.7,
            ),
        )

        _ = try await collectEvents(from: await agent.makeSession().send(
            "hello",
            turnOverrides: turnOverrides,
        ))

        #expect(
            await provider.recordedConfigurations() == [
                InferenceConfiguration(temperature: 0.7),
            ],
        )
    }
}
