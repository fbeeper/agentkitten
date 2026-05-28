// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import ArgumentParser

extension Playground {
    /// Demonstrates per-turn tool selection via a plan/code mode workflow.
    ///
    /// A scratchpad (a small Swift snippet) can only be read in plan mode.
    /// Once the model proposes a plan and the user approves, the session
    /// auto-transitions to code mode and the model executes its edits.
    /// Modes can also be switched manually with `/plan` or `/code`.
    struct PlanMode: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Plan/code mode demo: read-only tools in plan, write tools in code.",
        )

        @Option(name: .long, help: "Inference provider.")
        var provider: ProviderOption = .preferred

        @OptionGroup var providerOptions: ProviderEndpointOptions

        mutating func validate() throws {
            guard provider != .mock else {
                throw ValidationError("--provider mock is not supported for plan-mode.")
            }
        }

        func run() async throws {
            let scratchpad = ScratchpadStore()
            let modeState = PlanModeState()

            let agent = try PlaygroundSessionFactory.makeAgent(
                for: provider,
                behavior: AgentBehavior(systemPrompt: Self.systemPrompt),
                toolDefinition: ToolDefinition(
                    tools: [
                        AnyAgentTool(ReadScratchpadTool(store: scratchpad)),
                        AnyAgentTool(WriteScratchpadTool(store: scratchpad)),
                        AnyAgentTool(ProposePlanTool(state: modeState)),
                    ],
                    executionPolicy: PlanModeExecutionPolicy(state: modeState),
                ),
                endpoint: providerOptions.configuration,
            )
            print(
                PlaygroundChatOutputFormatter.sessionHeader(
                    title: "Plan Mode Demo",
                    detailLines: [
                        "AgentKitten Playground v\(AgentKitten.version)",
                        "Provider: \(provider.rawValue)",
                        "Scratchpad: a small Swift snippet you can ask the model to edit.",
                        "Starting in PLAN mode — the model can read but not write.",
                        "Use /plan or /code to switch modes manually.",
                    ],
                    instructions: "Type a message and press Enter. Use /show, /plan, /code. Ctrl-D to exit.",
                ),
            )
            try await chat(agent: agent, scratchpad: scratchpad, state: modeState)
            print()
            print("Goodbye!")
        }

        private func chat(agent: Agent, scratchpad: ScratchpadStore, state: PlanModeState) async throws {
            let session = agent.makeSession()
            while true {
                // Auto-send when the model just got a plan approved.
                if let plan = await state.consumeApprovedPlan() {
                    try await session.clearContext()
                    print()
                    print(PlaygroundChatOutputFormatter.assistantHeader(assistantLabel: "Assistant"))
                    flushStdout()
                    let turn = try await session.send(
                        Self.planApprovedPrompt(plan: plan),
                        turnOverrides: Self.codeOverrides,
                    )
                    do {
                        try await streamTurn(turn, suppressText: true)
                    } catch {
                        print(PlaygroundChatOutputFormatter.turnError(error))
                    }
                    print(PlaygroundChatOutputFormatter.separator)
                    continue
                }

                let mode = await state.mode
                print()
                print(Self.userPrompt(mode: mode))
                flushStdout()
                guard let line = readLine() else {
                    break
                }
                guard !line.isEmpty else {
                    continue
                }
                if await handleCommand(line, scratchpad: scratchpad, state: state) {
                    continue
                }
                await state.beginTurn()
                let overrides = Self.overrides(for: mode)
                let turn = try await session.send(line, turnOverrides: overrides)
                print()
                print(PlaygroundChatOutputFormatter.assistantHeader(assistantLabel: "Assistant"))
                flushStdout()
                do {
                    try await streamTurn(turn)
                } catch {
                    print(PlaygroundChatOutputFormatter.turnError(error))
                }
                print(PlaygroundChatOutputFormatter.separator)
            }
        }

        private func handleCommand(_ line: String, scratchpad: ScratchpadStore, state: PlanModeState) async -> Bool {
            switch line {
            case "/show":
                print(await scratchpad.content)
                return true
            case "/plan":
                await state.switchTo(.plan)
                print("[mode] Switched to PLAN mode. The model can read but not write the scratchpad.")
                return true
            case "/code":
                await state.switchTo(.code)
                print("[mode] Switched to CODE mode. The model can read and write the scratchpad.")
                return true
            default:
                return false
            }
        }

        private func streamTurn(
            _ turn: Turn<AssistantMessage>,
            suppressText: Bool = false,
        ) async throws {
            var streamedText = false
            for try await event in turn.events {
                switch event.kind {
                case .textDelta(let chunk):
                    guard !suppressText else {
                        break
                    }
                    streamedText = true
                    print(chunk, terminator: "")
                    flushStdout()
                case .result(let assistant):
                    if !streamedText, !suppressText {
                        print(assistant.text, terminator: "")
                    }
                    print()
                case .toolCallStarted(let name, _):
                    // propose_plan owns its own interaction UI; suppress the annotation for it.
                    guard name != ProposePlanTool.name else {
                        break
                    }
                    print("\n[tool:start] \(name)", terminator: "")
                    flushStdout()
                case .toolApprovalRequired:
                    break
                case .toolCallCompleted(let name, _, let outcome):
                    logToolCompletion(name: name, outcome: outcome)
                }
            }
        }

        private func logToolCompletion(name: String, outcome: ToolCallOutcome) {
            guard name != ProposePlanTool.name else {
                return
            }
            switch outcome {
            case .success:
                print("\n[tool:done] \(name)")
            case .failure(let failure):
                print("\n[tool:failed] \(name): \(failure.resultJSON)")
            }
            flushStdout()
        }

        private static func overrides(for mode: PlanModeState.Mode) -> TurnOverrides {
            switch mode {
            case .plan:
                TurnOverrides(
                    toolSelection: .including(["read_scratchpad", "propose_plan"]),
                    turnNote: planModeNote,
                )
            case .code:
                TurnOverrides(
                    toolSelection: .including(["read_scratchpad", "write_scratchpad"]),
                    turnNote: codeModeNote,
                )
            }
        }

        private static let codeOverrides = TurnOverrides(
            toolSelection: .including(["read_scratchpad", "write_scratchpad"]),
        )

        private static func planApprovedPrompt(plan: String) -> String {
            "[CODE MODE] Execute this plan.\n\n\(plan)\n\n" +
                "Get straight to the work. " +
                "Only narrate what changed if it helps the user understand the result."
        }

        private static func userPrompt(mode: PlanModeState.Mode) -> String {
            let tag = mode == .plan ? "[plan]" : "[code]"
            return "\(PlaygroundChatOutputFormatter.separator)\n\(tag) You:"
        }

        private static let systemPrompt = """
        You are a coding assistant working on a shared scratchpad file of Swift \
        source code. You operate in two modes indicated by [PLAN MODE] and \
        [CODE MODE] markers, each carrying specific instructions for that mode. \
        Never mention the mode system, tool names, or per-turn instructions to the user.
        """

        private static let planModeNote = """
        [PLAN MODE]
        Only call propose_plan when the user explicitly asks for a change to the \
        scratchpad. For greetings, questions, or discussion, just respond in text.
        When a change is requested, always read the scratchpad first, then call \
        propose_plan with a specific plan: numbered steps, exact signatures or \
        snippets for each change, and the expected final state.
        Do not write to the scratchpad. \
        Call propose_plan at most once; make no further tool calls after it returns.
        """

        private static let codeModeNote =
            "[CODE MODE] Read the scratchpad first, then execute the user's request. " +
            "Confirm what changed after writing."
    }
}
