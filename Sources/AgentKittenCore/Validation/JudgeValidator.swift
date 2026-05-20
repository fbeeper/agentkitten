// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0
// swiftlint:disable file_length

import Foundation

/// A validation policy backed by an internal structured judge agent.
///
/// `JudgeValidator` lowers the barrier to model-based validation by building a
/// dedicated inner `Agent` from concise validation criteria. Each validation
/// call creates a fresh inner session, asks the judge for a structured verdict,
/// and maps that verdict into ``ValidationResult``.
///
/// Tools are disabled by default but may be provided explicitly when the judge
/// needs external capabilities such as reference checking.
public struct JudgeValidator<Result: Codable & Sendable>: Validator {
    /// Discriminates how the judge's base system prompt is sourced.
    public enum Prompt: Sendable {
        /// AgentKitten builds the full judge system prompt from this criteria string.
        case criteria(String)
        /// Client supplies the full base prompt. Tools guidance is still appended automatically when tools are enabled.
        case systemPrompt(String)
    }

    /// Whether the inner judge may inspect session state.
    public enum SessionStateAccess: Sendable, Equatable {
        /// Do not expose session-state tools to the judge.
        case disabled
        /// Expose a read-only copy of session state to the judge via built-in tools.
        case readOnlyTools
    }

    /// Human-readable validator name recorded in trace validation entries.
    public let name: String
    /// Format string for the judge's system prompt when built from criteria; takes one `%@` argument.
    ///
    /// A best-effort check verifies the expected placeholder count at init time, but cannot
    /// guarantee the format string produces correct output. Callers are responsible for
    /// verifying behaviour end-to-end.
    public let judgeSystemPromptFormat: String
    /// Guidance appended to the system prompt instructing the judge how to return its verdict.
    public let judgeVerdictGuidance: String
    /// Format string for the judge's user prompt; takes two `%@` arguments (user message, candidate result).
    ///
    /// A best-effort check verifies the expected placeholder count at init time, but cannot
    /// guarantee the format string produces correct output. Callers are responsible for
    /// verifying behaviour end-to-end.
    public let judgeUserPromptFormat: String
    /// Fallback reason used when the judge rejects the result but provides no message.
    public let rejectedFallback: String
    /// Fallback message used when the judge requests a revised result but provides no message.
    public let revisedFallback: String

    private let prompt: Prompt
    private let providerRegistry: ProviderRegistry
    private let inferenceConfiguration: InferenceConfiguration
    private let toolBehavior: ToolBehavior
    private let toolDefinition: ToolDefinition
    private let sessionStateAccess: SessionStateAccess

    public var traceName: String {
        name
    }

    /// Creates a judge validator.
    ///
    /// - Parameters:
    ///   - prompt: How the judge's base system prompt is sourced — either a criteria string or a full custom prompt.
    ///   - providerRegistry: Providers available to the inner judge agent.
    ///   - inferenceConfiguration: Inference settings for the judge.
    ///   - toolBehavior: Tool execution behavior for the judge, including step budget.
    ///     Defaults to ``ToolBehavior/init()``.
    ///   - toolDefinition: Optional tools exposed to the judge. Defaults to no tools.
    ///   - sessionStateAccess: Whether the judge may inspect session state. Defaults to read-only tools.
    ///   - name: Validator name recorded in trace validation entries.
    ///   - judgeSystemPromptFormat: Format string for the judge system prompt (criteria case); takes one `%@`.
    ///   - judgeVerdictGuidance: Guidance appended to the system prompt for verdict format.
    ///   - judgeUserPromptFormat: Format string for the user prompt; takes two `%@` arguments.
    ///   - rejectedFallback: Fallback reason when the judge rejects without a message.
    ///   - revisedFallback: Fallback message when the judge requests revision without a message.
    public init(
        prompt: Prompt,
        providerRegistry: ProviderRegistry,
        inferenceConfiguration: InferenceConfiguration = InferenceConfiguration(),
        toolBehavior: ToolBehavior = ToolBehavior(),
        toolDefinition: ToolDefinition = .noTools,
        sessionStateAccess: SessionStateAccess = .readOnlyTools,
        name: String = "JudgeValidator",
        judgeSystemPromptFormat: String = Self.defaultJudgeSystemPromptFormat,
        judgeVerdictGuidance: String = Self.defaultJudgeVerdictGuidance,
        judgeUserPromptFormat: String = Self.defaultJudgeUserPromptFormat,
        rejectedFallback: String = Self.defaultJudgeRejectionMessage,
        revisedFallback: String = Self.defaultJudgeRevisionMessage,
    ) {
        precondition(
            judgeSystemPromptFormat.formatPlaceholderCount == 1,
            "judgeSystemPromptFormat must contain exactly one %@ placeholder for the criteria.",
        )
        precondition(
            judgeUserPromptFormat.formatPlaceholderCount == 2,
            "judgeUserPromptFormat must contain exactly two %@ placeholders (user message and candidate result).",
        )
        self.prompt = prompt
        self.name = name
        self.providerRegistry = providerRegistry
        self.inferenceConfiguration = inferenceConfiguration
        self.toolBehavior = toolBehavior
        self.toolDefinition = toolDefinition
        self.sessionStateAccess = sessionStateAccess
        self.judgeSystemPromptFormat = judgeSystemPromptFormat
        self.judgeVerdictGuidance = judgeVerdictGuidance
        self.judgeUserPromptFormat = judgeUserPromptFormat
        self.rejectedFallback = rejectedFallback
        self.revisedFallback = revisedFallback
    }

    /// Creates a judge validator using a single inference provider.
    ///
    /// A ``ProviderRegistry`` is created internally with `provider` as the default.
    /// Use this init for the common single-provider case to avoid registry boilerplate.
    ///
    /// - Parameters:
    ///   - prompt: How the judge's base system prompt is sourced — either a criteria string or a full custom prompt.
    ///   - provider: The inference provider to use for the inner judge agent.
    ///   - inferenceConfiguration: Inference settings for the judge.
    ///   - toolBehavior: Tool execution behavior for the judge, including step budget.
    ///     Defaults to ``ToolBehavior/init()``.
    ///   - toolDefinition: Optional tools exposed to the judge. Defaults to no tools.
    ///   - sessionStateAccess: Whether the judge may inspect session state. Defaults to read-only tools.
    ///   - name: Validator name recorded in trace validation entries.
    ///   - judgeSystemPromptFormat: Format string for the judge system prompt (criteria case); takes one `%@`.
    ///   - judgeVerdictGuidance: Guidance appended to the system prompt for verdict format.
    ///   - judgeUserPromptFormat: Format string for the user prompt; takes two `%@` arguments.
    ///   - rejectedFallback: Fallback reason when the judge rejects without a message.
    ///   - revisedFallback: Fallback message when the judge requests revision without a message.
    public init<Provider: InferenceProviding>(
        prompt: Prompt,
        provider: Provider,
        inferenceConfiguration: InferenceConfiguration = InferenceConfiguration(),
        toolBehavior: ToolBehavior = ToolBehavior(),
        toolDefinition: ToolDefinition = .noTools,
        sessionStateAccess: SessionStateAccess = .readOnlyTools,
        name: String = "JudgeValidator",
        judgeSystemPromptFormat: String = Self.defaultJudgeSystemPromptFormat,
        judgeVerdictGuidance: String = Self.defaultJudgeVerdictGuidance,
        judgeUserPromptFormat: String = Self.defaultJudgeUserPromptFormat,
        rejectedFallback: String = Self.defaultJudgeRejectionMessage,
        revisedFallback: String = "Judge requested a revised result.",
    ) {
        self.init(
            prompt: prompt,
            providerRegistry: ProviderRegistry(default: provider),
            inferenceConfiguration: inferenceConfiguration,
            toolBehavior: toolBehavior,
            toolDefinition: toolDefinition,
            sessionStateAccess: sessionStateAccess,
            name: name,
            judgeSystemPromptFormat: judgeSystemPromptFormat,
            judgeVerdictGuidance: judgeVerdictGuidance,
            judgeUserPromptFormat: judgeUserPromptFormat,
            rejectedFallback: rejectedFallback,
            revisedFallback: revisedFallback,
        )
    }

    public func validate(_ context: ValidationContext<Result>) async throws -> ValidationResult {
        let judgePrompt = makeJudgePrompt(from: context)
        let session = await makeJudgeSession(validationContext: context)
        let turn: Turn<JudgeDecision> = try await session.generate(judgePrompt)

        do {
            let decision = try await Self.firstResult(from: turn)
            return mapDecision(decision)
        } catch {
            return .error(message: String(describing: error))
        }
    }

    private func mapDecision(_ decision: JudgeDecision) -> ValidationResult {
        switch decision.verdict {
        case .pass:
            .pass
        case .fail:
            .fail(reason: decision.resolvedMessage(fallback: rejectedFallback))
        case .feedback:
            .feedback(message: decision.resolvedMessage(fallback: revisedFallback))
        }
    }

    private func makeJudgeSession(
        validationContext: ValidationContext<Result>,
    ) async -> AgentSession {
        let trace = AgentTrace(retentionPolicy: .maxTurns(0))
        let stateConfiguration = await makeJudgeStateConfiguration(
            validationContext: validationContext,
            trace: trace,
        )

        let approvalGate = ToolApprovalGate()
        let behavior = AgentBehavior(
            systemPrompt: stateConfiguration.systemPrompt,
            phaseBehaviors: PhaseBehaviorSet(base: PhaseBehavior(inferenceConfiguration: inferenceConfiguration)),
        )
        return AgentSession(
            sessionID: .generate(),
            agentID: .generate(),
            ownerID: validationContext.userMessage.sender,
            trace: trace,
            state: stateConfiguration.state,
            approvalGate: approvalGate,
            behavior: behavior,
            toolBehavior: toolBehavior,
            conversationFactory: ConversationAssembler(
                phaseBehaviors: behavior.phaseBehaviors,
                providerRegistry: providerRegistry,
                baseSystemPrompt: behavior.systemPrompt,
                toolDefinition: stateConfiguration.toolDefinition,
                runtimeConfig: toolBehavior.runtimeConfig,
                toolApprovalGate: approvalGate,
            ),
        )
    }
}

extension JudgeValidator {
    private struct JudgeStateConfiguration {
        let state: AgentSession.SessionStateAccess
        let toolDefinition: ToolDefinition
        let systemPrompt: String
    }

    private func makeJudgeStateConfiguration(
        validationContext: ValidationContext<Result>,
        trace: AgentTrace,
    ) async -> JudgeStateConfiguration {
        switch sessionStateAccess {
        case .disabled:
            return makeDefaultJudgeStateConfiguration()
        case .readOnlyTools:
            switch validationContext.sessionState {
            case .disabled:
                return makeDefaultJudgeStateConfiguration()
            case .readOnly(let outerState), .enabled(let outerState):
                let copiedState = await outerState.contents()
                let readOnlyState = SessionState.readOnly(
                    trace: trace,
                    contents: copiedState,
                )
                let toolDefinition = toolDefinition.replacing(
                    registry: toolDefinition.registry.adding(
                        SessionStateBuiltins.makeReadOnlyTools(state: readOnlyState),
                    ),
                )
                let systemPrompt = makeJudgeSystemPrompt(prompt: prompt, hasTools: true)
                    + "\n\n"
                    + SessionStateConfiguration.defaultPromptGuidance
                    + "\n\n"
                    + SessionStateConfiguration.readOnlyPromptGuidance
                return JudgeStateConfiguration(
                    state: .readOnly(readOnlyState),
                    toolDefinition: toolDefinition,
                    systemPrompt: systemPrompt,
                )
            }
        }
    }

    private func makeDefaultJudgeStateConfiguration() -> JudgeStateConfiguration {
        JudgeStateConfiguration(
            state: .disabled,
            toolDefinition: toolDefinition,
            systemPrompt: makeJudgeSystemPrompt(
                prompt: prompt,
                hasTools: !toolDefinition.registry.all.isEmpty,
            ),
        )
    }

    private func makeJudgeSystemPrompt(
        prompt: Prompt,
        hasTools: Bool,
    ) -> String {
        let base: String = switch prompt {
        case .criteria(let criteriaString):
            String(
                format: judgeSystemPromptFormat,
                criteriaString.trimmingCharacters(in: .whitespacesAndNewlines),
            )
        case .systemPrompt(let rawPrompt):
            rawPrompt
        }
        var sections = [base, judgeVerdictGuidance]
        if hasTools {
            sections.append(ToolBehavior.defaultGuidancePrompt)
        }
        return sections.joined(separator: "\n\n")
    }

    private func makeJudgePrompt(
        from context: ValidationContext<Result>,
    ) -> String {
        let resultDescription = Self.encodeResult(context.result)
        return String(
            format: judgeUserPromptFormat,
            context.userMessage.text,
            resultDescription,
        )
    }

    private static func encodeResult(_ result: Result) -> String {
        // Text turns are the common judge case, so keep assistant responses as
        // plain text instead of JSON-wrapping them. This type check is an
        // intentionally small internal shortcut; if judge input rendering grows
        // beyond this split, lift it into a dedicated rendering abstraction.
        if let assistantMessage = result as? AssistantMessage {
            return assistantMessage.text
        }

        do {
            let data = try JSONEncoder.judgeEncoder.encode(result)
            guard let json = String(data: data, encoding: .utf8) else {
                return String(describing: result)
            }
            return json
        } catch {
            return String(describing: result)
        }
    }

    private static func firstResult<T: Sendable>(
        from turn: Turn<T>,
    ) async throws -> T {
        for try await event in turn.events {
            if case .result(let result) = event.kind {
                return result
            }
        }
        throw JudgeValidatorError.missingResult
    }
}

extension JSONEncoder {
    fileprivate static let judgeEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private struct JudgeDecision: Codable, Sendable, JSONSchemaProviding {
    enum Verdict: String, Codable, Sendable {
        case pass
        case fail
        case feedback
    }

    let verdict: Verdict
    let message: String?

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "verdict": .enumeration(
                    values: ["pass", "fail", "feedback"],
                    description: "The validation verdict.",
                ),
                "message": .string(
                    description: "Reason for fail or feedback text for retry.",
                ),
            ],
            required: ["verdict"],
        )
    }

    func resolvedMessage(fallback: String) -> String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private enum JudgeValidatorError: Error {
    case missingResult
}

extension JudgeValidator {
    /// Default format string for the judge system prompt (criteria case); takes one `%@`.
    public static var defaultJudgeSystemPromptFormat: String {
        """
        You are a validation judge for another AI assistant's response.

        Evaluate the candidate result against the original user request and the \
        validation criteria below.

        Validation criteria:
        %@

        Prefer feedback over fail when a revised answer could satisfy the criteria. \
        Use fail only when the result should be rejected rather than retried.
        """
    }

    /// Default guidance appended to the system prompt for verdict format.
    public static var defaultJudgeVerdictGuidance: String {
        """
        Return one structured decision:
        - pass: the result satisfies the criteria
        - fail: the result is invalid and should be rejected
        - feedback: the result could be improved by another assistant attempt
        """
    }

    /// Default format string for the judge user prompt; takes two `%@` arguments.
    public static var defaultJudgeUserPromptFormat: String {
        """
        Original user message:
        %1$@

        Candidate result:
        %2$@

        Evaluate the candidate result against the criteria from your system \
        instructions and return the structured verdict.
        """
    }

    /// Default fallback reason when the judge rejects without a message.
    public static var defaultJudgeRejectionMessage: String {
        "Judge rejected the result."
    }

    /// Default fallback message when the judge requests revision without a message.
    public static var defaultJudgeRevisionMessage: String {
        "Judge requested a revised result."
    }
}
