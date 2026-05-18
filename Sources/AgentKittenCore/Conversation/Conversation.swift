// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One thread of interaction with an agent, generic over the inference provider.
///
/// `Conversation` is an internal actor owned by `AgentSession`. It drives
/// inference for a single provider session. Clients do not interact with
/// `Conversation` directly — use ``AgentSession/send(_:)`` instead.
///
/// `AgentSession` calls ``send(userMessage:)`` to start an inference turn. The
/// returned stream emits `ConversationEvent<AssistantMessage>` values and finishes when the
/// turn completes.
/// Cancellation propagates from the consumer into the work task via
/// `continuation.onTermination`.
actor Conversation<Provider: InferenceProviding> {
    /// Stable identity of this conversation lane.
    let conversationID: ConversationID
    /// The user who owns this conversation.
    let owner: UserID

    private let provider: Provider
    private let systemPrompt: String
    private struct SessionSlot {
        let id: InferenceSessionID
        let session: Provider.Session
    }

    private var sessionSlot: SessionSlot
    private let digester: InferenceDigester
    private let operationGate = SingleFlightOperationGate<InferenceSessionOperationKind> {
        InferenceError.concurrentOperationInProgress(active: $0)
    }

    init(
        owner: UserID,
        provider: Provider,
        systemPrompt: String,
        executionConfiguration: EffectiveExecutionConfiguration,
        toolRuntime: ToolRuntime,
    ) {
        conversationID = .generate()
        self.owner = owner
        self.provider = provider
        self.systemPrompt = systemPrompt
        let inferenceContext = executionConfiguration.inferenceContext
        let session = provider.makeSession(
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            toolSelection: executionConfiguration.toolSelection,
            inferenceContext: inferenceContext,
        )
        sessionSlot = SessionSlot(id: .generate(), session: session)
        digester = InferenceDigester()
    }

    /// Replaces the inner provider session, preserving conversation identity and history.
    ///
    /// Called when ``SessionCompatibility/rebuildSession`` is signalled for a
    /// turn-configuration transition. The provider is asked to construct a new session
    /// that continues from the current one (e.g. by passing the prior trace or
    /// history), then the current session is atomically replaced.
    func rebuildSession(
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws {
        let lease = try operationGate.begin(.rebuildSession)
        defer {
            lease.end()
        }
        let session = try await provider.makeSession(
            continuing: sessionSlot.session,
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            inferenceContext: inferenceContext,
        )
        sessionSlot = SessionSlot(id: .generate(), session: session)
    }

    func identity() -> ConversationIdentity {
        ConversationIdentity(
            conversationID: conversationID,
            inferenceSessionID: sessionSlot.id,
        )
    }

    func contextUsage() async throws -> ContextUsage {
        let lease = try operationGate.begin(.contextUsage)
        defer {
            lease.end()
        }
        return try await sessionSlot.session.contextUsage()
    }

    /// Runs a single inference turn for `userMessage` and returns the inner event stream.
    ///
    /// Creates an `AsyncThrowingStream` of ``ConversationEvent`` values. Spawns an unstructured
    /// `Task` (justified: stream init is synchronous and we cannot `await` the Task here). The
    /// Task drives generation, emits the terminal `.result(AssistantMessage)`, and finishes the
    /// stream.
    ///
    /// `continuation.onTermination` cancels the spawned Task so that stopping iteration of
    /// the returned stream propagates cancellation into the inference work.
    func send(
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        toolExecutionContext: ToolExecutionContext,
    ) throws -> AsyncThrowingStream<ConversationEvent<AssistantMessage>, Error> {
        let lease = try operationGate.begin(.run)
        let (stream, continuation) = AsyncThrowingStream<ConversationEvent<AssistantMessage>, Error>.makeStream()
        // Unstructured Task justified: AsyncThrowingStream init is synchronous; we cannot
        // await the Task here. The Task is cancelled via continuation.onTermination below.
        // Lease is released in runTurn (not onTermination) so the gate stays held until the
        // underlying session is fully done, preventing session-gate races on immediate re-send.
        let task = Task {
            await self.runTurn(
                continuation: continuation,
                userMessage: userMessage,
                executionConfiguration: executionConfiguration,
                toolExecutionContext: toolExecutionContext,
                lease: lease,
            )
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Starts a structured generation on the conversation-owned session.
    func generate<T: Codable & Sendable & JSONSchemaProviding>(
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        toolExecutionContext: ToolExecutionContext,
    ) async throws -> AsyncThrowingStream<ConversationEvent<T>, Error> {
        let lease = try operationGate.begin(.generate)
        do {
            let parameters = InferenceRequestParameters(
                configuration: executionConfiguration.inferenceConfiguration,
                toolStepBudget: executionConfiguration.toolStepBudget,
                toolSelection: executionConfiguration.toolSelection,
                toolExecutionContext: toolExecutionContext,
                inferenceContext: executionConfiguration.inferenceContext,
            )
            let inferenceStream: StructuredInferenceStream<T> =
                try await sessionSlot.session.generateStream(prompt: userMessage.text, parameters: parameters)
            let (stream, continuation) = AsyncThrowingStream<ConversationEvent<T>, Error>.makeStream()
            let task = Task {
                await self.runStructuredTurn(
                    stream: inferenceStream,
                    continuation: continuation,
                    lease: lease,
                )
            }
            continuation.onTermination = { _ in task.cancel() }
            return stream
        } catch {
            lease.end()
            throw error
        }
    }

    /// Drives generation and finishes the stream.
    private func runTurn(
        continuation: AsyncThrowingStream<ConversationEvent<AssistantMessage>, Error>.Continuation,
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        toolExecutionContext: ToolExecutionContext,
        lease: SingleFlightOperationGate<InferenceSessionOperationKind>.Lease,
    ) async {
        defer {
            lease.end()
        }
        do {
            let parameters = InferenceRequestParameters(
                configuration: executionConfiguration.inferenceConfiguration,
                toolStepBudget: executionConfiguration.toolStepBudget,
                toolSelection: executionConfiguration.toolSelection,
                toolExecutionContext: toolExecutionContext,
                inferenceContext: executionConfiguration.inferenceContext,
            )
            let stream = try await sessionSlot.session.run(userMessage, parameters: parameters)
            try await digester.digest(
                stream: stream,
                continuation: continuation,
                conversationID: conversationID,
            )
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func runStructuredTurn<T: Codable & Sendable & JSONSchemaProviding>(
        stream: StructuredInferenceStream<T>,
        continuation: AsyncThrowingStream<ConversationEvent<T>, Error>.Continuation,
        lease: SingleFlightOperationGate<InferenceSessionOperationKind>.Lease,
    ) async {
        defer {
            lease.end()
        }
        do {
            try await digester.digestStructured(
                stream: stream,
                continuation: continuation,
                conversationID: conversationID,
            )
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}

extension Conversation: StructuredConversation {}

// MARK: - Context compaction

extension Conversation {
    /// Replaces the inner provider session with a compacted continuation.
    ///
    /// Deliberately combines compact and rebuild under one gate lease. Both steps are async
    /// suspension points; splitting them across two separate gate acquisitions would leave a
    /// window where another operation could interleave between a compacted-but-not-yet-rebuilt
    /// session and the rebuild. Holding a single `.rebuildSession` lease across both closes
    /// that window.
    func rebuildSession(
        compacting options: ContextCompactionOptions,
        summaryGenerator: ContextCompactionSummaryGenerator,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws -> ContextCompactionResult {
        let lease = try operationGate.begin(.rebuildSession)
        defer {
            lease.end()
        }
        guard let compactable = sessionSlot.session as? any ContextCompactableSession else {
            throw InferenceError.unsupportedConfiguration(
                "The active provider session does not support context compaction.",
            )
        }
        let result = await ContextCompactor().compact(
            compactable,
            options: options,
            summaryGenerator: summaryGenerator,
        )
        let session = try await provider.makeSession(
            continuing: sessionSlot.session,
            systemPrompt: systemPrompt,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            inferenceContext: inferenceContext,
        )
        sessionSlot = SessionSlot(id: .generate(), session: session)
        return result
    }

    package func compactContext(
        options: ContextCompactionOptions,
        summaryGenerator: ContextCompactionSummaryGenerator,
    ) async throws -> ContextCompactionResult {
        let lease = try operationGate.begin(.compactContext)
        defer {
            lease.end()
        }
        guard let compactable = sessionSlot.session as? any ContextCompactableSession else {
            throw InferenceError.unsupportedConfiguration(
                "The active provider session does not support context compaction.",
            )
        }
        return await ContextCompactor().compact(
            compactable,
            options: options,
            summaryGenerator: summaryGenerator,
        )
    }
}
