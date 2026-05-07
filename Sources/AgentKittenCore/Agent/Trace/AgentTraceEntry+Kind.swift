// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension AgentTraceEntry {
    /// The semantic kind of one durable trace entry.
    public enum Kind: Sendable, Codable, Equatable, Hashable {
        /// Start of a turn with the triggering user input.
        case turnStarted(UserMessage)
        /// A durable message emitted during a turn, including tool calls, tool
        /// results, and completed assistant messages.
        ///
        /// Tool messages are appended eagerly and may therefore appear even when
        /// the enclosing turn later ends as cancelled or failed.
        case message(AgentMessage)
        /// A generic structured terminal result captured as raw JSON.
        case structuredResult(type: String, json: String)
        /// Turn-scoped execution preparation metadata.
        case executionPreparation(ExecutionPreparationInfo)
        /// Resolved conversation identity after preparation succeeds.
        case conversationResolved(ConversationResolvedInfo)
        /// Session context compaction metadata.
        case contextCompaction(ContextCompactionInfo)
        /// A session-state mutation recorded without the raw value payload.
        case stateMutation(StateMutation)
        /// A model-requested tool call is waiting on caller approval.
        case toolApprovalRequired(ToolApprovalRequiredInfo)
        /// A ``ToolHook`` fired during tool execution. Recorded for auditability.
        case toolHookFired(ToolHookInvocationInfo)
        /// Validation activity recorded during assistant-response handling.
        case validation(ValidationInfo)
        /// A runtime error recorded during the turn.
        case error(ErrorInfo)
        /// The terminal outcome of the turn.
        case turnCompleted(TurnOutcome)

        private enum CodingKeys: String, CodingKey {
            case type
            case userMessage
            case message
            case resultType
            case resultJSON
            case executionPreparation
            case conversationResolved
            case contextCompaction
            case outcome
            case stateMutation
            case pendingToolCall
            case toolHookFired
            case validation
            case error
        }

        private enum CaseKind: String, Codable {
            case turnStarted
            case message
            case structuredResult
            case executionPreparation
            case conversationResolved
            case contextCompaction
            case stateMutation
            case toolApprovalRequired
            case toolHookFired
            case validation
            case error
            case turnCompleted
        }

        // swiftlint:disable:next cyclomatic_complexity
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(CaseKind.self, forKey: .type)
            switch kind {
            case .turnStarted:
                self = .turnStarted(try container.decode(UserMessage.self, forKey: .userMessage))
            case .message:
                self = .message(try container.decode(AgentMessage.self, forKey: .message))
            case .structuredResult:
                self = .structuredResult(
                    type: try container.decode(String.self, forKey: .resultType),
                    json: try container.decode(String.self, forKey: .resultJSON)
                )
            case .executionPreparation:
                self = .executionPreparation(
                    try container.decode(ExecutionPreparationInfo.self, forKey: .executionPreparation)
                )
            case .conversationResolved:
                self = .conversationResolved(
                    try container.decode(ConversationResolvedInfo.self, forKey: .conversationResolved)
                )
            case .contextCompaction:
                self = .contextCompaction(
                    try container.decode(Self.ContextCompactionInfo.self, forKey: .contextCompaction)
                )
            case .stateMutation:
                self = .stateMutation(try container.decode(StateMutation.self, forKey: .stateMutation))
            case .toolApprovalRequired:
                self = .toolApprovalRequired(
                    try container.decode(ToolApprovalRequiredInfo.self, forKey: .pendingToolCall)
                )
            case .toolHookFired:
                self = .toolHookFired(
                    try container.decode(ToolHookInvocationInfo.self, forKey: .toolHookFired)
                )
            case .validation:
                self = .validation(try container.decode(ValidationInfo.self, forKey: .validation))
            case .error:
                self = .error(try container.decode(ErrorInfo.self, forKey: .error))
            case .turnCompleted:
                self = .turnCompleted(try container.decode(TurnOutcome.self, forKey: .outcome))
            }
        }

        // swiftlint:disable:next cyclomatic_complexity
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .turnStarted(let userMessage):
                try container.encode(CaseKind.turnStarted, forKey: .type)
                try container.encode(userMessage, forKey: .userMessage)
            case .message(let message):
                try container.encode(CaseKind.message, forKey: .type)
                try container.encode(message, forKey: .message)
            case .structuredResult(let type, let json):
                try container.encode(CaseKind.structuredResult, forKey: .type)
                try container.encode(type, forKey: .resultType)
                try container.encode(json, forKey: .resultJSON)
            case .executionPreparation(let info):
                try container.encode(CaseKind.executionPreparation, forKey: .type)
                try container.encode(info, forKey: .executionPreparation)
            case .conversationResolved(let info):
                try container.encode(CaseKind.conversationResolved, forKey: .type)
                try container.encode(info, forKey: .conversationResolved)
            case .contextCompaction(let info):
                try container.encode(CaseKind.contextCompaction, forKey: .type)
                try container.encode(info, forKey: .contextCompaction)
            case .stateMutation(let stateMutation):
                try container.encode(CaseKind.stateMutation, forKey: .type)
                try container.encode(stateMutation, forKey: .stateMutation)
            case .toolApprovalRequired(let pendingToolCall):
                try container.encode(CaseKind.toolApprovalRequired, forKey: .type)
                try container.encode(pendingToolCall, forKey: .pendingToolCall)
            case .toolHookFired(let info):
                try container.encode(CaseKind.toolHookFired, forKey: .type)
                try container.encode(info, forKey: .toolHookFired)
            case .validation(let validation):
                try container.encode(CaseKind.validation, forKey: .type)
                try container.encode(validation, forKey: .validation)
            case .error(let error):
                try container.encode(CaseKind.error, forKey: .type)
                try container.encode(error, forKey: .error)
            case .turnCompleted(let outcome):
                try container.encode(CaseKind.turnCompleted, forKey: .type)
                try container.encode(outcome, forKey: .outcome)
            }
        }
    }
}

extension AgentTraceEntry.Kind {
    /// Durable trace metadata for a tool call waiting on caller approval.
    public struct ToolApprovalRequiredInfo: Sendable, Codable, Equatable, Hashable {
        /// The pending tool call awaiting approval.
        public let call: PendingToolCall
        /// Tool-approval execution-context values visible to the policy, if any.
        public let context: CustomContextSnapshot?

        /// Creates trace metadata for an approval-required tool call.
        public init(
            call: PendingToolCall,
            context: CustomContextSnapshot? = nil
        ) {
            self.call = call
            self.context = context
        }
    }

    /// Durable trace metadata for a session context compaction attempt.
    public struct ContextCompactionInfo: Sendable, Codable, Equatable, Hashable {
        /// Whether the compaction was requested manually or by automatic policy.
        public enum Mode: String, Sendable, Codable, Equatable, Hashable {
            /// Client-requested compaction.
            case manual
            /// Automatic start-of-turn compaction.
            case automatic
        }

        /// Compaction mode.
        public let mode: Mode
        /// Provider used for compaction summary generation, when resolved.
        public let provider: ProviderReferenceSnapshot?
        /// Inference configuration used for compaction summary generation, when resolved.
        public let inferenceConfiguration: InferenceConfigurationSnapshot?
        /// Custom inference-context values used for compaction summary generation, when resolved.
        public let inferenceContext: CustomContextSnapshot?
        /// Compaction result.
        public let result: ContextCompactionResult

        /// Creates trace metadata for context compaction.
        public init(
            mode: Mode,
            provider: ProviderReferenceSnapshot? = nil,
            inferenceConfiguration: InferenceConfigurationSnapshot? = nil,
            inferenceContext: CustomContextSnapshot? = nil,
            result: ContextCompactionResult
        ) {
            self.mode = mode
            self.provider = provider
            self.inferenceConfiguration = inferenceConfiguration
            self.inferenceContext = inferenceContext
            self.result = result
        }
    }
}
