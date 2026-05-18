// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import AgentKittenCore
import AgentKittenInference
import Darwin

/// Factories for creating inference sessions and agents in the Playground.
///
/// Centralises provider selection, platform availability checks, and error
/// propagation so every Playground command constructs sessions and agents
/// the same way without repeating the `switch`/conditional-compilation pattern.
enum PlaygroundSessionFactory {

    /// Creates a ``ToolRuntime`` from a flat list of tools and an execution policy.
    ///
    /// - Parameters:
    ///   - tools: Tools to register. Defaults to none.
    ///   - policy: Execution policy. Defaults to auto-approve.
    static func makeToolRuntime(
        tools: [AnyAgentTool] = [],
        policy: AnyToolExecutionPolicy = AnyToolExecutionPolicy(AutoApprovePolicy()),
    ) -> ToolRuntime {
        ToolRuntime(configuration: ToolDefinition(tools: tools, executionPolicy: policy))
    }

    /// Creates a session for the given provider option.
    ///
    /// The returned session conforms to both ``InferenceSession`` and
    /// ``StructuredInferenceSession`` — use either protocol depending on the
    /// command's needs. Throws ``PlaygroundError`` when Apple Intelligence
    /// is unavailable.
    ///
    /// - Parameters:
    ///   - option: Provider requested by the caller.
    ///   - systemPrompt: System prompt for the session. Defaults to `nil` (none).
    ///   - runtime: Tool runtime to bind to the session.
    static func makeSession(
        for option: ProviderOption,
        systemPrompt: String? = nil,
        runtime: ToolRuntime,
    ) throws -> any InferenceSession & StructuredInferenceSession {
        switch option {
        case .mock:
            return InferenceProvider.mock().makeSession(
                systemPrompt: systemPrompt,
                toolRuntime: runtime,
                toolSelection: .all,
                inferenceContext: .empty,
            )
        case .anthropic:
            return InferenceProvider.anthropic().makeSession(
                systemPrompt: systemPrompt,
                toolRuntime: runtime,
                toolSelection: .all,
                inferenceContext: .empty,
            )
        case .apple:
            #if canImport(FoundationModels)
            if #available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *) {
                return InferenceProvider.apple().makeSession(
                    systemPrompt: systemPrompt,
                    toolRuntime: runtime,
                    toolSelection: .all,
                    inferenceContext: .empty,
                )
            }
            throw PlaygroundError.appleIntelligenceRequiresMacOS26
            #else
            throw PlaygroundError.appleIntelligenceNeedsFoundationModels
            #endif
        }
    }

    /// Creates a single-provider ``Agent`` for the given provider option.
    ///
    /// Throws ``PlaygroundError`` when Apple Intelligence is unavailable.
    ///
    /// - Parameters:
    ///   - option: Provider requested by the caller.
    ///   - behavior: The agent behavior, including its system prompt.
    ///   - toolDefinition: Tool set and execution policy. Defaults to no tools, auto-approve.
    static func makeAgent(
        for option: ProviderOption,
        behavior: AgentBehavior,
        toolDefinition: ToolDefinition = ToolDefinition(),
    ) throws -> Agent {
        Agent(
            providerRegistry: try PlaygroundProviderFactory.makeRegistry(for: option),
            behavior: behavior,
            toolDefinition: toolDefinition,
        )
    }

    /// Creates an ``Agent`` from an already-built provider registry.
    ///
    /// Used by Playground commands that need multiple registered providers, such
    /// as cross-provider context compaction or a custom default/override setup.
    static func makeAgent(
        providerRegistry: ProviderRegistry,
        behavior: AgentBehavior,
        toolDefinition: ToolDefinition,
        sessionState: SessionStateMode = .disabled,
    ) -> Agent {
        return Agent(
            providerRegistry: providerRegistry,
            behavior: behavior,
            toolDefinition: toolDefinition,
            sessionState: sessionState,
        )
    }

    /// Creates a single-provider ``Agent`` for the given provider option.
    ///
    /// - Parameters:
    ///   - provider: Provider requested by the caller.
    ///   - behavior: The agent behavior, including its system prompt.
    ///   - toolDefinition: Tool set and execution policy. Defaults to no tools, auto-approve.
    ///   - sessionState: Whether to expose built-in session-state scratchpad tools.
    static func makeAgent(
        provider: ProviderOption,
        behavior: AgentBehavior,
        toolDefinition: ToolDefinition = ToolDefinition(),
        sessionState: SessionStateMode = .disabled,
    ) throws -> Agent {
        Agent(
            providerRegistry: try PlaygroundProviderFactory.makeRegistry(for: provider),
            behavior: behavior,
            toolDefinition: toolDefinition,
            sessionState: sessionState,
        )
    }

    /// Streams one agent turn to stdout.
    ///
    /// Handles text deltas, tool approval (interactive when `toolPolicy == .ask`),
    /// and verbose tool-event logging under a single `--verbose-tools` gate.
    ///
    /// **Verbose format** (`[tool:start]`, `[tool:done]`, `[tool:failed]`) includes
    /// the tool call ID and trimmed output so callers get consistent output across commands.
    ///
    /// - Parameters:
    ///   - turn: The turn returned by `AgentSession.send(_:)`.
    ///   - session: The active agent session, needed for interactive approval resolution.
    ///   - toolPolicy: Governs interactive vs. automatic approval.
    ///   - memory: Tracks tools the user previously approved with "always".
    ///   - verboseTools: When `true`, logs tool start/completion events. Defaults to `false`.
    static func streamTurn(
        _ turn: Turn<AssistantMessage>,
        session: any ToolApproving,
        toolPolicy: Playground.ToolPolicyOption,
        memory: PlaygroundToolApprovalMemory,
        verboseTools: Bool = false,
    ) async throws {
        var streamedAssistantText = false
        for try await event in turn.events {
            switch event.kind {
            case .textDelta(let chunk):
                streamedAssistantText = true
                print(chunk, terminator: "")
                fflush(stdout)
            case .result(let assistant):
                if !streamedAssistantText {
                    print(assistant.text, terminator: "")
                }
                print()
            case .toolCallStarted(let name, let id):
                guard verboseTools else {
                    break
                }
                print("\n[tool:start] \(name) (\(id))", terminator: "")
                fflush(stdout)
            case .toolApprovalRequired(let call):
                try await handleApproval(
                    call: call,
                    agentContext: (session, turn),
                    memory: memory,
                    toolPolicy: toolPolicy,
                    verboseTools: verboseTools,
                )
            case .toolCallCompleted(let name, let id, let outcome):
                guard verboseTools else {
                    break
                }
                logToolCompletion(name: name, id: id, outcome: outcome)
            }
        }
    }

    private static func handleApproval(
        call: PendingToolCall,
        agentContext: (session: any ToolApproving, turn: Turn<AssistantMessage>),
        memory: PlaygroundToolApprovalMemory,
        toolPolicy: Playground.ToolPolicyOption,
        verboseTools: Bool,
    ) async throws {
        if toolPolicy == .ask {
            _ = try await PlaygroundToolApprovalPrompt.resolve(
                call: call,
                session: agentContext.session,
                turn: agentContext.turn,
                memory: memory,
            )
        } else if verboseTools {
            print("\n\(PlaygroundToolEventFormatter.approvalRequired(call))", terminator: "")
            fflush(stdout)
        }
    }

    private static func logToolCompletion(name: String, id: ToolCallID, outcome: ToolCallOutcome) {
        switch outcome {
        case .success(let content):
            let text = content.compactMap { item -> String? in
                guard case .text(let text) = item else {
                    return nil
                }
                return text
            }.joined(separator: "\n")
            print("\n[tool:done] \(name) (\(id)) -> \(PlaygroundTracePrinter.trim(text))")
        case .failure(let failure):
            print(
                "\n[tool:failed] \(name) (\(id)) -> " +
                    PlaygroundTracePrinter.trim(failure.resultJSON),
            )
        }
        fflush(stdout)
    }
}
