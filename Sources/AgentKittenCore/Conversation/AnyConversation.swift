// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Type-erasure wrapper for a concrete `Conversation<Provider>`.
///
/// `AnyConversation` uses direct closure capture for non-generic operations and
/// a minimal protocol existential only for structured generation.
struct AnyConversation: Sendable {
    private let sendClosure:
        @Sendable (
            UserMessage,
            EffectiveExecutionConfiguration,
            ToolExecutionContext
        ) async throws -> AsyncThrowingStream<ConversationEvent<AssistantMessage>, Error>
    private let identityClosure: @Sendable () async -> ConversationIdentity
    private let contextUsageClosure: @Sendable () async throws -> ContextUsage
    private let compactContextClosure:
        @Sendable (
            ContextCompactionOptions,
            ContextCompactionSummaryGenerator
        ) async throws -> ContextCompactionResult
    private let rebuildSessionClosure:
        @Sendable (ToolRuntime, ToolSelection, InferenceContext) async throws -> Void
    private let rebuildCompactedSessionClosure:
        @Sendable (
            ContextCompactionOptions,
            ContextCompactionSummaryGenerator,
            ToolRuntime,
            ToolSelection,
            InferenceContext
        ) async throws -> ContextCompactionResult
    private let structuredConversation: any StructuredConversation

    init<Provider: InferenceProviding>(
        conversation: Conversation<Provider>,
    ) {
        self.sendClosure = { userMessage, executionConfiguration, toolExecutionContext in
            try await conversation.send(
                userMessage: userMessage,
                executionConfiguration: executionConfiguration,
                toolExecutionContext: toolExecutionContext,
            )
        }
        self.identityClosure = {
            await conversation.identity()
        }
        self.contextUsageClosure = {
            try await conversation.contextUsage()
        }
        self.compactContextClosure = { options, summaryGenerator in
            try await conversation.compactContext(
                options: options,
                summaryGenerator: summaryGenerator,
            )
        }
        self.rebuildSessionClosure = { toolRuntime, toolSelection, inferenceContext in
            try await conversation.rebuildSession(
                toolRuntime: toolRuntime,
                toolSelection: toolSelection,
                inferenceContext: inferenceContext,
            )
        }
        self.rebuildCompactedSessionClosure = { opts, summaryGenerator, runtime, selection, context in
            try await conversation.rebuildSession(
                compacting: opts,
                summaryGenerator: summaryGenerator,
                toolRuntime: runtime,
                toolSelection: selection,
                inferenceContext: context,
            )
        }
        self.structuredConversation = conversation
    }

    func identity() async -> ConversationIdentity {
        await identityClosure()
    }

    func contextUsage() async throws -> ContextUsage {
        try await contextUsageClosure()
    }

    package func compactContext(
        options: ContextCompactionOptions,
        summaryGenerator: ContextCompactionSummaryGenerator,
    ) async throws -> ContextCompactionResult {
        try await compactContextClosure(options, summaryGenerator)
    }

    /// Replaces the inner provider session, preserving conversation identity and history.
    func rebuildSession(
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws {
        try await rebuildSessionClosure(toolRuntime, toolSelection, inferenceContext)
    }

    /// Replaces the inner provider session with a compacted continuation.
    func rebuildSession(
        compacting options: ContextCompactionOptions,
        summaryGenerator: ContextCompactionSummaryGenerator,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws -> ContextCompactionResult {
        try await rebuildCompactedSessionClosure(
            options,
            summaryGenerator,
            toolRuntime,
            toolSelection,
            inferenceContext,
        )
    }

    /// Runs a single inference turn for `userMessage` and returns the inner event stream.
    ///
    /// Calling actor-isolated methods on `Conversation` requires `await`, so this
    /// method is async.
    func send(
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        toolExecutionContext: ToolExecutionContext,
    ) async throws -> AsyncThrowingStream<ConversationEvent<AssistantMessage>, Error> {
        try await sendClosure(userMessage, executionConfiguration, toolExecutionContext)
    }

    /// Starts a structured generation and returns the typed event stream.
    func generate<T: Codable & Sendable & JSONSchemaProviding>(
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        toolExecutionContext: ToolExecutionContext,
    ) async throws -> AsyncThrowingStream<ConversationEvent<T>, Error> {
        try await structuredConversation.generate(
            userMessage: userMessage,
            executionConfiguration: executionConfiguration,
            toolExecutionContext: toolExecutionContext,
        )
    }
}

protocol StructuredConversation: Sendable {
    func generate<T: Codable & Sendable & JSONSchemaProviding>(
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        toolExecutionContext: ToolExecutionContext,
    ) async throws -> AsyncThrowingStream<ConversationEvent<T>, Error>
}
