// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import AgentKittenInferenceTestSupport
import ArgumentParser
import Foundation

extension Playground {
    /// Demonstrates tool calling end-to-end with two built-in demo tools.
    ///
    /// On macOS 26+ the Apple on-device provider is used; tools are bridged via
    /// `AppleBridgedTool` and executed by the model. On older OS versions or non-Apple
    /// platforms a ``PlaygroundError`` is thrown. Pass `--provider mock` to run the
    /// scripted demo flow without requiring Apple Intelligence.
    struct Tools: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Tool-calling demo with CurrentTime and ConvertTemperature tools.",
        )

        @Option(name: .long, help: "The prompt to send. Defaults to a prompt that exercises both tools.")
        var prompt: String?

        private var effectivePrompt: String {
            if let prompt { return prompt }
            if imageDemo { return "Please get an image and describe in detail what you see in it." }
            return "What time is it right now, and what is 100°F in Celsius?"
        }

        @Option(name: .long, help: "System prompt for the agent.")
        var system: String = "You are a helpful assistant. Use the provided tools when relevant."

        @Option(name: .long, help: "Inference provider.")
        var provider: ProviderOption = .preferred

        @OptionGroup var providerOptions: ProviderEndpointOptions

        @Option(name: .long, help: "Tool execution policy: approve, ask, or deny.")
        var toolPolicy: ToolPolicyOption = .approve

        @Flag(name: .long, help: "Print trace entries for each turn after the response completes.")
        var trace = false

        @Flag(name: .long, help: "Print live tool call and tool result events while the turn is running.")
        var verboseTools = false

        @Flag(
            name: .long,
            help: "Register the bundled rich image demo tool (`fixture_image`).",
        )
        var imageDemo = false

        func run() async throws {
            print("AgentKitten Playground v\(AgentKitten.version) — tools demo")
            print("Prompt: \(effectivePrompt)\n")

            var tools: [AnyAgentTool] = [
                AnyAgentTool(CurrentTimeTool()),
                AnyAgentTool(ConvertTemperatureTool()),
            ]
            if imageDemo {
                tools.append(AnyAgentTool(FixtureImageTool()))
            }
            let toolDefinition = ToolDefinition(
                tools: tools,
                executionPolicy: PlaygroundToolApprovalPrompt.configuredPolicy(for: toolPolicy),
            )
            switch provider {
            case .mock:
                try await runMock(toolDefinition: toolDefinition)
            #if canImport(Darwin) || canImport(FoundationNetworking)
            case .anthropic:
                let agent = try PlaygroundSessionFactory.makeAgent(
                    for: provider,
                    behavior: AgentBehavior(systemPrompt: system),
                    toolDefinition: toolDefinition,
                    endpoint: providerOptions.configuration,
                )
                try await runConversation(agent: agent, prompt: effectivePrompt)
            case .openai:
                let agent = try PlaygroundSessionFactory.makeAgent(
                    for: provider,
                    behavior: AgentBehavior(systemPrompt: system),
                    toolDefinition: toolDefinition,
                    endpoint: providerOptions.configuration,
                )
                try await runConversation(agent: agent, prompt: effectivePrompt)
            #endif
            #if canImport(FoundationModels)
            case .apple:
                let agent = try PlaygroundSessionFactory.makeAgent(
                    for: provider,
                    behavior: AgentBehavior(systemPrompt: system),
                    toolDefinition: toolDefinition,
                )
                try await runConversation(agent: agent, prompt: effectivePrompt)
            #endif
            }
        }

        private func runConversation(agent: Agent, prompt: String) async throws {
            let session = agent.makeQueuedSession()
            let memory = PlaygroundToolApprovalMemory()
            let turn = await session.send(prompt)
            print("Assistant: ", terminator: "")
            flushStdout()
            try await PlaygroundSessionFactory.streamTurn(
                turn,
                session: session,
                toolPolicy: toolPolicy,
                memory: memory,
                verboseTools: verboseTools,
            )
            if trace {
                await PlaygroundTracePrinter.printTurnTrace(
                    trace: session.trace,
                    invocationID: turn.id,
                )
            }
        }

        private func runMock(toolDefinition: ToolDefinition) async throws {
            // NOTE: `prompt` (the --prompt option) is intentionally ignored here.
            // The mock provider uses scripted responses, so the input text has no
            // effect on which tools fire or what the model "says". Two fixed turns
            // are driven so both tools are exercised regardless of the prompt.
            // Each session.send() advances the mock session by one response.
            let provider = MockInferenceProvider(mockResponses: [
                .toolCall(
                    name: CurrentTimeTool.name,
                    argumentsJSON: "{}",
                    thenRespond: "(mock) The tool returned the current time.",
                ),
                .toolCall(
                    name: ConvertTemperatureTool.name,
                    argumentsJSON: #"{"value":100,"from":"fahrenheit","toUnit":"celsius"}"#,
                    thenRespond: "(mock) The tool converted 100°F to Celsius.",
                ),
            ])
            let behavior = AgentBehavior(
                systemPrompt: """
                You are a helpful assistant. Use the provided tools when relevant.
                """,
            )
            let agent = Agent(
                providerRegistry: ProviderRegistry(default: provider),
                behavior: behavior,
                toolDefinition: toolDefinition,
            )
            let session = agent.makeQueuedSession()
            let memory = PlaygroundToolApprovalMemory()
            for turnPrompt in ["What time is it?", "What is 100°F in Celsius?"] {
                let turn = await session.send(turnPrompt)
                print("\nUser: \(turnPrompt)")
                print("Assistant: ", terminator: "")
                flushStdout()
                try await PlaygroundSessionFactory.streamTurn(
                    turn,
                    session: session,
                    toolPolicy: toolPolicy,
                    memory: memory,
                    verboseTools: verboseTools,
                )
                if trace {
                    await PlaygroundTracePrinter.printTurnTrace(
                        trace: session.trace,
                        invocationID: turn.id,
                    )
                }
            }
        }
    }
}
