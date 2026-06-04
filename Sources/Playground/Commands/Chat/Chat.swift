// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import ArgumentParser

extension Playground {
    /// Multi-turn conversation that exercises the Agent layer.
    ///
    /// Reads prompts from stdin one line at a time. Ctrl-D exits.
    struct Chat: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Multi-turn chat via Agent. Ctrl-D to exit.",
        )

        @Option(name: .long, help: "System prompt for the agent.")
        var system: String = "You are a helpful assistant."

        @Option(name: .long, help: "Inference provider.")
        var provider: ProviderOption = .preferred

        @OptionGroup var providerOptions: ProviderEndpointOptions

        @Option(name: .long, help: "Tool execution policy: approve, ask, or deny.")
        var toolPolicy: ToolPolicyOption = .approve

        @Flag(name: .long, help: "Print trace entries for each turn after the response completes.")
        var trace = false

        @Flag(name: .long, help: "Enable built-in session-state scratchpad tools for the chat session.")
        var sessionState = false

        @Flag(name: .long, help: "Print live tool call and tool result events while the turn is running.")
        var verboseTools = false

        @Option(
            name: .long,
            help: "Minimum accepted assistant response length. Responses shorter than this are retried.",
        )
        var minResponseLength: Int = 0

        @Option(
            name: .long,
            help: "Judge criteria used to validate assistant responses with a judge agent.",
        )
        var judgeCriteria: String = ""

        @Option(
            name: .long,
            help: "Inference provider for the judge agent. Defaults to --provider.",
        )
        var judgeProvider: ProviderOption?

        @Option(
            name: .long,
            help: "Enable automatic compaction at this fraction (0–1) of the context window. Needs a known window.",
        )
        var compactionPercent: Double?

        @Option(
            name: .long,
            help: "Enable automatic compaction at this many tokens. Works without a known window.",
        )
        var compactionTokens: Int?

        @Option(
            name: .long,
            help: "Context-window override (tokens) for endpoints that can't report it. Drives /usage and compaction.",
        )
        var contextWindow: Int?

        @Option(name: .long, help: "Inference provider for context compaction. Defaults to --provider.")
        var compactionProvider: ProviderOption?

        @Flag(name: .long, help: "Print current provider context usage after each turn.")
        var showUsage = false

        func validate() throws {
            if compactionPercent != nil, compactionTokens != nil {
                throw ValidationError("--compaction-percent and --compaction-tokens are mutually exclusive.")
            }
            if let compactionPercent, compactionPercent <= 0 || compactionPercent > 1 {
                throw ValidationError("--compaction-percent must be greater than 0 and at most 1.")
            }
            if let compactionTokens, compactionTokens < 0 {
                throw ValidationError("--compaction-tokens must not be negative.")
            }
            try validateContextWindow()
        }

        func run() async throws {
            let effectiveJudgeProvider = judgeProvider ?? provider
            printSessionHeader(judgeProvider: effectiveJudgeProvider)
            let agent = try makeAgent()
            try await chat(
                agent: agent,
                judgeCriteria: judgeCriteria,
                judgeProvider: effectiveJudgeProvider,
            )
        }

        private func chat(
            agent: Agent,
            judgeCriteria: String,
            judgeProvider: ProviderOption,
        ) async throws {
            let session = agent.makeSession()
            let memory = PlaygroundToolApprovalMemory()
            let validation = try makeValidationConfiguration(
                judgeCriteria: judgeCriteria,
                judgeProvider: judgeProvider,
            )
            // readLine() blocks the current thread. Acceptable in a single-turn
            // CLI playground — no concurrent work needs the thread while waiting.
            while true {
                print()
                print(PlaygroundChatOutputFormatter.userPrompt())
                flushStdout()
                guard let line = readLine(), !line.isEmpty else {
                    break
                }
                if await handleCommandPrintingErrors(line, session: session) {
                    continue
                }
                let turn = if let validation {
                    try await session.send(line, validation: validation)
                } else {
                    try await session.send(line)
                }
                print()
                print(PlaygroundChatOutputFormatter.assistantHeader(assistantLabel: "Assistant"))
                flushStdout()
                do {
                    try await PlaygroundSessionFactory.streamTurn(
                        turn,
                        session: session,
                        toolPolicy: toolPolicy,
                        memory: memory,
                        verboseTools: verboseTools,
                    )
                } catch {
                    print(PlaygroundChatOutputFormatter.turnError(error))
                }
                if trace {
                    await PlaygroundTracePrinter.printTurnTrace(
                        trace: session.trace,
                        invocationID: turn.id,
                    )
                }
                if showUsage {
                    await printContextUsage(session: session)
                }
                print(PlaygroundChatOutputFormatter.separator)
            }
            print()
            print("Goodbye!")
        }

        private func printContextUsage(session: AgentSession) async {
            do {
                let usage = try await session.contextUsage()
                print(PlaygroundChatOutputFormatter.contextUsage(usage))
            } catch AgentSessionError.noActiveConversation {
                print(PlaygroundChatOutputFormatter.contextUsage(nil))
            } catch {
                print(PlaygroundChatOutputFormatter.turnError(error))
            }
        }

        private func handleCommandPrintingErrors(_ line: String, session: AgentSession) async -> Bool {
            do {
                return try await handleCommand(line, session: session)
            } catch {
                print(PlaygroundChatOutputFormatter.turnError(error))
                return true
            }
        }

        private func handleCommand(_ line: String, session: AgentSession) async throws -> Bool {
            switch line {
            case "/clear":
                try await clear(session: session)
            case "/clear-keep-state":
                try await clearKeepingState(session: session)
            case "/compact":
                try await compact(session: session)
            case "/usage":
                await printContextUsage(session: session)
            default:
                return false
            }
            return true
        }

        private func clear(session: AgentSession) async throws {
            if sessionState {
                try await session.clearContext()
                print("Context and session state cleared.")
            } else {
                try await session.clearContext(state: .preserve)
                print("Context cleared.")
            }
        }

        private func clearKeepingState(session: AgentSession) async throws {
            try await session.clearContext(state: .preserve)
            print("Context cleared. Session state preserved.")
        }

        private func compact(session: AgentSession) async throws {
            let result = try await session.compactContext()
            switch result {
            case .compacted(let info):
                let before = info.usageBefore.contextTokens
                let after = info.usageAfter.contextTokens
                print("Context compacted: \(before) → \(after) tokens.")
                if showUsage {
                    await printContextUsage(session: session)
                }
            case .skipped(let reason):
                print("Compaction skipped: \(reason).")
            }
        }

        private func makeValidationConfiguration(
            judgeCriteria: String,
            judgeProvider: ProviderOption,
        ) throws -> ValidationConfiguration<AssistantMessage>? {
            let trimmedJudgeCriteria = judgeCriteria.trimmingCharacters(
                in: .whitespacesAndNewlines,
            )

            guard !trimmedJudgeCriteria.isEmpty else {
                if minResponseLength > 0 {
                    return ValidationConfiguration(
                        validator: MinimumResponseLengthValidator(
                            minimumLength: minResponseLength,
                        ),
                        maxRetries: 2,
                    )
                }
                return nil
            }

            var validation: ValidationConfiguration<AssistantMessage>?
            if minResponseLength > 0 {
                validation = ValidationConfiguration(
                    validator: MinimumResponseLengthValidator(
                        minimumLength: minResponseLength,
                    ),
                    maxRetries: 2,
                    policy: .permissive,
                )
            }

            let judge = JudgeValidator<AssistantMessage>(
                prompt: .criteria(trimmedJudgeCriteria),
                providerRegistry: try PlaygroundProviderFactory.makeJudgeRegistry(
                    for: judgeProvider,
                    endpoint: providerOptions.configuration,
                ),
                name: "PlaygroundJudge",
            )

            if let validation {
                return validation.adding(judge)
            }

            return ValidationConfiguration(
                validator: judge,
                maxRetries: 2,
                policy: .permissive,
            )
        }
    }
}

extension Playground.Chat {
    private func printSessionHeader(judgeProvider: ProviderOption) {
        print(
            PlaygroundChatOutputFormatter.sessionHeader(
                title: "Chat",
                detailLines: sessionDetailLines(judgeProvider: judgeProvider),
                instructions: PlaygroundChatOutputFormatter.chatInstructions,
            ),
        )
    }

    private func sessionDetailLines(judgeProvider: ProviderOption) -> [String] {
        var detailLines = [
            "AgentKitten Playground v\(AgentKitten.version)",
            "System: \(system)",
            "Default provider: \(provider.rawValue)",
            "Tool policy: \(toolPolicy.rawValue)",
            "Session state: \(sessionState ? "enabled" : "disabled")",
            "Compaction: \(compactionPercent != nil || compactionTokens != nil ? "enabled" : "disabled")",
            "Show usage: \(showUsage ? "enabled" : "disabled")",
            "Min response length: \(minResponseLength)",
        ]
        if let compactionPercent {
            detailLines.append("Compaction trigger: \(Int(compactionPercent * 100))% of context window")
        }
        if let compactionTokens {
            detailLines.append("Compaction trigger: \(compactionTokens) tokens")
        }
        if let contextWindow {
            detailLines.append("Context window override: \(contextWindow) tokens")
        }
        if let compactionProvider {
            detailLines.append("Compaction provider: \(compactionProvider.rawValue)")
        }
        let trimmedJudgeCriteria = judgeCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedJudgeCriteria.isEmpty {
            detailLines.append("Judge provider: \(judgeProvider.rawValue)")
            detailLines.append("Judge criteria: \(judgeCriteria)")
            detailLines.append("Judge policy: permissive after retry exhaustion")
        }
        return detailLines
    }

    private func makeAgent() throws -> Agent {
        let providerConfiguration = try PlaygroundProviderFactory.makeRegistry(
            default: provider,
            compaction: compactionProvider,
            endpoint: providerOptions.configuration,
        )
        return PlaygroundSessionFactory.makeAgent(
            providerRegistry: providerConfiguration.registry,
            behavior: makeBehavior(compactionProvider: providerConfiguration.compactionProvider),
            toolDefinition: makeToolDefinition(),
            sessionState: sessionState ? .enabledWithDefaultGuidance : .disabled,
        )
    }

    private func makeBehavior(compactionProvider: ProviderReference?) -> AgentBehavior {
        var base = PhaseBehavior()
        applyContextWindow(to: &base)
        var phaseBehaviors = PhaseBehaviorSet(base: base)
        if let compactionProvider {
            phaseBehaviors.set(
                PhaseBehavior(provider: compactionProvider),
                for: .compaction,
            )
        }
        return AgentBehavior(
            systemPrompt: system,
            phaseBehaviors: phaseBehaviors,
            defaultAutomaticCompactionPolicy: compactionPolicy(),
        )
    }

    /// Resolves the automatic compaction policy from the `--compaction-percent` and
    /// `--compaction-tokens` options. Passing either one enables compaction; an
    /// absolute-token trigger works even when the context window is unknown, while a
    /// percent trigger needs a known window. They are mutually exclusive (see `validate()`).
    private func compactionPolicy() -> AutomaticCompactionPolicy {
        if let compactionTokens {
            return .enabled(trigger: .absoluteTokens(UInt(compactionTokens)))
        }
        if let compactionPercent {
            return .enabled(trigger: .percentOfContextWindow(compactionPercent))
        }
        return .disabled
    }

    private func makeToolDefinition() -> ToolDefinition {
        ToolDefinition(
            tools: [
                AnyAgentTool(CurrentTimeTool()),
                AnyAgentTool(ConvertTemperatureTool()),
            ],
            executionPolicy: PlaygroundToolApprovalPrompt.configuredPolicy(for: toolPolicy),
        )
    }
}
