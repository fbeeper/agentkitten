// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

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
    public init(
        prompt: Prompt,
        providerRegistry: ProviderRegistry,
        inferenceConfiguration: InferenceConfiguration = .init(),
        toolBehavior: ToolBehavior = .init(),
        toolDefinition: ToolDefinition = .noTools,
        sessionStateAccess: SessionStateAccess = .readOnlyTools,
        name: String = "JudgeValidator",
    ) {
        self.prompt = prompt
        self.name = name
        self.providerRegistry = providerRegistry
        self.inferenceConfiguration = inferenceConfiguration
        self.toolBehavior = toolBehavior
        self.toolDefinition = toolDefinition
        self.sessionStateAccess = sessionStateAccess
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
    public init<Provider: InferenceProviding>(
        prompt: Prompt,
        provider: Provider,
        inferenceConfiguration: InferenceConfiguration = .init(),
        toolBehavior: ToolBehavior = .init(),
        toolDefinition: ToolDefinition = .noTools,
        sessionStateAccess: SessionStateAccess = .readOnlyTools,
        name: String = "JudgeValidator",
    ) {
        self.init(
            prompt: prompt,
            providerRegistry: ProviderRegistry(default: provider),
            inferenceConfiguration: inferenceConfiguration,
            toolBehavior: toolBehavior,
            toolDefinition: toolDefinition,
            sessionStateAccess: sessionStateAccess,
            name: name,
        )
    }

    public func validate(_ context: ValidationContext<Result>) async throws -> ValidationResult {
        let prompt = Self.makeJudgePrompt(from: context)
        let session = await makeJudgeSession(validationContext: context)
        let turn: Turn<JudgeDecision> = try await session.generate(prompt)

        do {
            let decision = try await Self.firstResult(from: turn)
            return decision.validationResult
        } catch {
            return .error(message: String(describing: error))
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
            phaseBehaviors: .init(base: .init(inferenceConfiguration: inferenceConfiguration)),
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
                rationaleSchemaDescription: toolBehavior.rationaleGuidance.schemaDescription,
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
                let systemPrompt = Self.makeJudgeSystemPrompt(prompt: prompt, hasTools: true)
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
            systemPrompt: Self.makeJudgeSystemPrompt(
                prompt: prompt,
                hasTools: !toolDefinition.registry.all.isEmpty,
            ),
        )
    }

    private static func makeJudgeSystemPrompt(
        prompt: Prompt,
        hasTools: Bool,
    ) -> String {
        let base: String
        switch prompt {
        case .criteria(let criteriaString):
            base = AgentKittenLocalization.formattedString(
                "validation.judgeSystemPromptFormat",
                criteriaString.trimmingCharacters(in: .whitespacesAndNewlines),
            )
        case .systemPrompt(let rawPrompt):
            base = rawPrompt
        }
        var sections = [base, AgentKittenLocalization.string("validation.judgeVerdictGuidance")]
        if hasTools {
            sections.append(ToolBehavior.Guidance.defaultPrompt)
        }
        return sections.joined(separator: "\n\n")
    }

    private static func makeJudgePrompt(
        from context: ValidationContext<Result>,
    ) -> String {
        let resultDescription = encodeResult(context.result)
        return AgentKittenLocalization.formattedString(
            "validation.judgeUserPromptFormat",
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
                    description: AgentKittenLocalization.string("validation.verdictDescription"),
                ),
                "message": .string(
                    description: AgentKittenLocalization.string("validation.messageDescription"),
                ),
            ],
            required: ["verdict"],
        )
    }

    var validationResult: ValidationResult {
        switch verdict {
        case .pass:
            return .pass
        case .fail:
            return .fail(reason: resolvedMessage(
                fallback: AgentKittenLocalization.string("validation.rejectedFallback"),
            ))
        case .feedback:
            return .feedback(message: resolvedMessage(
                fallback: AgentKittenLocalization.string("validation.revisedFallback"),
            ))
        }
    }

    private func resolvedMessage(fallback: String) -> String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private enum JudgeValidatorError: Error {
    case missingResult
}
