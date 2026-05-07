// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

@Suite("Judge Validator System Prompt")
struct JudgeValidatorSystemPromptTests {
    @Test func judgeValidator_systemPromptUsedVerbatim() async throws {
        let customPrompt = "You are a strict content reviewer. Approve only safe responses."
        let outerProvider = ScriptedInferenceProvider(
            responses: [.success("Candidate response")],
        )
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [.success(#"{"verdict":"pass"}"#)],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: outerProvider),
            behavior: .test("Answer the user.")
        )
        let session = agent.makeSession()

        let turn = try await session.send(
            "Hi",
            validation: ValidationConfiguration(
                validator: JudgeValidator<AssistantMessage>(
                    prompt: .systemPrompt(customPrompt),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                    name: "Custom Prompt Judge"
                )
            )
        )
        _ = try await collectEvents(from: turn)

        let latestPrompt = await judgeProvider.script.latestPrompt()
        #expect(latestPrompt?.hasPrefix(customPrompt) == true)
        #expect(latestPrompt?.contains("judgeSystemPromptFormat") == false)
        #expect(latestPrompt?.contains("Return one structured decision") == true)
    }

    @Test func judgeValidator_systemPromptAppendsToolsGuidanceWhenToolsEnabled() async throws {
        let counter = ToolCallCounter()
        let customPrompt = "You are a strict content reviewer."
        let outerProvider = ScriptedInferenceProvider(
            responses: [.success("Candidate response")],
        )
        let judgeProvider = ScriptedInferenceProvider(
            structuredResponses: [
                .toolCall(
                    name: CountingEchoTool.name,
                    argumentsJSON: #"{"message":"hi"}"#,
                    thenRespond: #"{"verdict":"pass"}"#
                ),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: outerProvider),
            behavior: .test("Answer the user.")
        )
        let session = agent.makeSession()

        let turn = try await session.send(
            "Hi",
            validation: ValidationConfiguration(
                validator: JudgeValidator<AssistantMessage>(
                    prompt: .systemPrompt(customPrompt),
                    providerRegistry: ProviderRegistry(default: judgeProvider),
                    toolDefinition: ToolDefinition(
                        tools: [AnyAgentTool(CountingEchoTool(counter: counter))]
                    )
                )
            )
        )
        let events = try await collectEvents(from: turn)

        #expect(assistantCompletions(in: events) == ["Candidate response"])
        #expect(await counter.value() == 1)
        let latestPrompt = await judgeProvider.script.latestPrompt()
        #expect(latestPrompt?.hasPrefix(customPrompt) == true)
        #expect(latestPrompt?.contains(ToolBehavior.Guidance.defaultPrompt) == true)
    }
}
