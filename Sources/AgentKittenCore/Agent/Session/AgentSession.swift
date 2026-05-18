// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Runtime session for one interaction thread derived from an ``Agent`` definition.
///
/// `AgentSession` owns all mutable runtime state: one compatible reusable
/// direct-execution conversation and the durable trace for this session.
///
/// Conversation-affecting operations are single-flight. Start one of `send`,
/// `generate`, `clearContext`, `compactContext`, or `contextUsage` only when no
/// other such operation is active, or use ``AgentQueuedSession`` for FIFO
/// queueing behavior.
public actor AgentSession: ToolApproving {
    /// Session-state availability for this session.
    public enum SessionStateAccess: Sendable {
        /// Session state is disabled for this session.
        case disabled
        /// Session state is available for inspection but not mutation.
        case readOnly(SessionState)
        /// Session state is fully enabled.
        case enabled(SessionState)

        var sessionState: SessionState? {
            switch self {
            case .disabled:
                nil
            case .readOnly(let state), .enabled(let state):
                state
            }
        }

        func beginTurn(invocationID: InvocationID) async {
            guard let sessionState else {
                return
            }
            await sessionState.beginTurn(invocationID: invocationID)
        }

        func endTurn() async {
            guard let sessionState else {
                return
            }
            await sessionState.endTurn()
        }

        public func value(forKey key: String) async -> SessionStateValue? {
            guard let sessionState else {
                return nil
            }
            return await sessionState.value(forKey: key)
        }

        func contents() async -> [String: SessionStateValue] {
            guard let sessionState else {
                return [:]
            }
            return await sessionState.contents()
        }
    }

    /// The unique identifier for this session.
    public nonisolated let sessionID: AgentSessionID
    /// The parent agent definition identifier.
    public nonisolated let agentID: AgentID
    /// The user who owns this session.
    public nonisolated let ownerID: UserID
    /// Durable record of runtime activity across this session's lifetime.
    public let trace: AgentTrace
    /// Mutable scratchpad storage shared across turns in this session.
    public let state: SessionStateAccess
    /// Gate that suspends tool calls requiring interactive approval.
    let approvalGate: ToolApprovalGate

    private let runtime: AgentSessionRuntime
    let agentEnvironment: ExecutionEnvironment
    let operationGate = SingleFlightOperationGate<InferenceSessionOperationKind> {
        AgentSessionError.concurrentOperationInProgress(active: $0)
    }
    // Internal setter: mutate only via setAutomaticCompactionPolicy(_:).
    public internal(set) var automaticCompactionPolicy: AutomaticCompactionPolicy
    // Internal for conversation-preparation helpers in the split AgentSession extension file.
    var conversationProvider: ConversationProvider

    init(
        sessionID: AgentSessionID,
        agentID: AgentID,
        ownerID: UserID,
        trace: AgentTrace,
        state: SessionStateAccess,
        approvalGate: ToolApprovalGate,
        behavior: AgentBehavior,
        toolBehavior: ToolBehavior,
        conversationFactory: ConversationAssembler,
    ) {
        self.sessionID = sessionID
        self.agentID = agentID
        self.ownerID = ownerID
        self.trace = trace
        self.state = state
        self.approvalGate = approvalGate
        self.agentEnvironment = ExecutionEnvironment(behavior: behavior, toolBehavior: toolBehavior)
        self.automaticCompactionPolicy = behavior.defaultAutomaticCompactionPolicy
        self.conversationProvider = ConversationProvider(
            owner: ownerID,
            factory: conversationFactory,
        )
        self.runtime = AgentSessionRuntime(
            agentID: agentID,
            sessionID: sessionID,
            trace: trace,
            approvalGate: approvalGate,
            state: state,
        )
    }

    /// Approves a pending tool call for this session.
    ///
    /// Call this after receiving ``AgentEvent.Kind/toolApprovalRequired(_:)``.
    ///
    /// - Parameter callID: The pending tool call identifier to approve.
    public func approve(callID: ToolCallID) async throws {
        try await approvalGate.approve(callID: callID)
    }

    /// Denies a pending tool call for this session.
    ///
    /// Call this after receiving ``AgentEvent.Kind/toolApprovalRequired(_:)``.
    ///
    /// - Parameters:
    ///   - callID: The pending tool call identifier to deny.
    ///   - reason: The denial reason surfaced back through the tool failure path.
    public func deny(callID: ToolCallID, reason: String) async throws {
        try await approvalGate.deny(callID: callID, reason: reason)
    }

    /// Starts a user message turn immediately when the session is idle.
    ///
    /// - Parameters:
    ///   - text: The user's message text.
    ///   - userID: The user to attribute this message to. Defaults to the session owner.
    ///   - validation: Validation policy applied to the assistant response.
    /// - Returns: A ``Turn`` handle for this active turn.
    public func send(
        _ text: String,
        userID: UserID? = nil,
        validation: ValidationConfiguration<AssistantMessage> = .disabled,
    ) async throws -> Turn<AssistantMessage> {
        try await send(
            text,
            userID: userID,
            turnOverrides: .init(),
            validation: validation,
        )
    }

    /// Starts a user message turn immediately when the session is idle.
    ///
    /// - Parameters:
    ///   - text: The user's message text.
    ///   - userID: The user to attribute this message to. Defaults to the session owner.
    ///   - turnOverrides: Full per-turn execution override.
    ///   - validation: Validation policy applied to the assistant response.
    /// - Returns: A ``Turn`` handle for this active turn.
    public func send(
        _ text: String,
        userID: UserID? = nil,
        turnOverrides: TurnOverrides,
        validation: ValidationConfiguration<AssistantMessage> = .disabled,
    ) async throws -> Turn<AssistantMessage> {
        let turn = makeAssistantTurn(
            text,
            userID: userID,
            turnOverrides: turnOverrides,
        )
        try await startAssistantTurn(
            turn,
            validation: validation,
            operation: .run,
        )
        return turn
    }

    /// Starts a structured generation immediately when the session is idle.
    ///
    /// - Parameters:
    ///   - prompt: The prompt describing the generation task.
    ///   - userID: The user to attribute this generation to. Defaults to the session owner.
    ///   - validation: Validation policy applied to the structured result.
    /// - Returns: A typed ``Turn`` handle for this active generation.
    public func generate<Result: Codable & Sendable & JSONSchemaProviding>(
        _ prompt: String,
        userID: UserID? = nil,
        validation: ValidationConfiguration<Result> = .disabled,
    ) async throws -> Turn<Result> {
        try await generate(
            prompt,
            userID: userID,
            turnOverrides: .init(),
            validation: validation,
        )
    }

    /// Starts a structured generation immediately when the session is idle.
    ///
    /// - Parameters:
    ///   - prompt: The prompt describing the generation task.
    ///   - userID: The user to attribute this generation to. Defaults to the session owner.
    ///   - turnOverrides: Full per-turn execution override.
    ///   - validation: Validation policy applied to the structured result.
    /// - Returns: A typed ``Turn`` handle for this active generation.
    public func generate<Result: Codable & Sendable & JSONSchemaProviding>(
        _ prompt: String,
        userID: UserID? = nil,
        turnOverrides: TurnOverrides,
        validation: ValidationConfiguration<Result> = .disabled,
    ) async throws -> Turn<Result> {
        let turn: Turn<Result> = makeStructuredTurn(
            prompt,
            userID: userID,
            turnOverrides: turnOverrides,
        )
        try await startStructuredTurn(
            turn,
            validation: validation,
            operation: .generate,
        )
        return turn
    }

    /// Performs one queued turn's session-owned lifecycle.
    ///
    /// This composes the user message, prepares the provider conversation,
    /// records trace lifecycle entries, delegates concrete execution to
    /// `executePreparedTurn`, and finishes the outer turn stream.
    private func performTurn<Result: Sendable>(
        _ turnRuntime: TurnRuntime<Result>,
        lease: SingleFlightOperationGate<InferenceSessionOperationKind>.Lease,
        executePreparedTurn: @Sendable (UserMessage, AnyConversation) async throws -> Void,
    ) async {
        let userMessage = userMessage(for: turnRuntime)
        await state.beginTurn(invocationID: turnRuntime.id)
        do {
            let conversation = try await conversation(
                executionEnvironment: turnRuntime.executionEnvironment,
                turnOverrides: turnRuntime.requestedTurnOverrides,
                invocationID: turnRuntime.id,
            )
            record(kind: .turnStarted(userMessage), invocationID: turnRuntime.id)
            try await executePreparedTurn(userMessage, conversation)
            record(kind: .turnCompleted(.completed), invocationID: turnRuntime.id)
            turnRuntime.continuation.finish()
        } catch is CancellationError {
            record(kind: .turnCompleted(.cancelled), invocationID: turnRuntime.id)
            turnRuntime.continuation.finish()
        } catch {
            let agentError = AgentTraceEntry.Kind.ErrorInfo(error)
            record(kind: .error(agentError), invocationID: turnRuntime.id)
            record(kind: .turnCompleted(.failed(agentError)), invocationID: turnRuntime.id)
            turnRuntime.continuation.finish(throwing: error)
        }
        await state.endTurn()
        lease.end()
    }

    /// Composes the outbound ``UserMessage`` for a turn.
    ///
    /// Prepends ``TurnOverrides/turnNote`` to the turn text when present,
    /// separated by a blank line, so the model sees note and message as one
    /// coherent user turn.
    private func userMessage<Result: Sendable>(for turnRuntime: TurnRuntime<Result>) -> UserMessage {
        let composedText = turnRuntime.requestedTurnOverrides.turnNote.map { $0 + "\n\n" + turnRuntime.text }
            ?? turnRuntime.text
        return UserMessage(text: composedText, sender: turnRuntime.sender)
    }

}

// MARK: - Turn startup

extension AgentSession {
    func makeAssistantTurn(
        _ text: String,
        userID: UserID?,
        turnOverrides: TurnOverrides,
    ) -> Turn<AssistantMessage> {
        let userID = userID ?? ownerID
        assert(userID == ownerID, "Message sender \(userID) does not match session owner \(ownerID).")
        let turnEnvironment = agentEnvironment.overlaying(turnOverrides)
        return Turn<AssistantMessage>(
            id: .generate(),
            text: text,
            sender: userID,
            requestedTurnOverrides: turnOverrides,
            executionEnvironment: turnEnvironment,
        )
    }

    func makeStructuredTurn<Result: Codable & Sendable & JSONSchemaProviding>(
        _ prompt: String,
        userID: UserID?,
        turnOverrides: TurnOverrides,
    ) -> Turn<Result> {
        let userID = userID ?? ownerID
        assert(userID == ownerID, "Message sender \(userID) does not match session owner \(ownerID).")
        let turnEnvironment = agentEnvironment.overlaying(turnOverrides)
        return Turn<Result>(
            id: .generate(),
            text: prompt,
            sender: userID,
            requestedTurnOverrides: turnOverrides,
            executionEnvironment: turnEnvironment,
        )
    }

    @discardableResult
    func startAssistantTurn(
        _ turn: Turn<AssistantMessage>,
        validation: ValidationConfiguration<AssistantMessage>,
        operation: InferenceSessionOperationKind,
    ) async throws -> Task<Void, Never> {
        let lease = try operationGate.begin(operation)
        let turnRuntime = turn.runtime
        let task = Task<Void, Never> {
            await self.performTurn(turnRuntime, lease: lease) { userMessage, conversation in
                try await self.runtime.routeTurn(
                    userMessage: userMessage,
                    turnRuntime: turnRuntime,
                    validation: validation,
                    conversation: conversation,
                )
            }
        }
        // Install termination before registering the task on `Turn`: `startAssistantTurn`
        // still holds `turn` strongly during this setup, so drop-cancellation cannot race
        // ahead of `markRunning`, while early stream termination still cancels the task.
        turnRuntime.continuation.onTermination = { _ in task.cancel() }
        let started = await turn.markRunning(task: task)
        if !started {
            task.cancel()
            _ = await task.value
            lease.end()
        }
        return task
    }

    @discardableResult
    func startStructuredTurn<Result: Codable & Sendable & JSONSchemaProviding>(
        _ turn: Turn<Result>,
        validation: ValidationConfiguration<Result>,
        operation: InferenceSessionOperationKind,
    ) async throws -> Task<Void, Never> {
        let lease = try operationGate.begin(operation)
        let turnRuntime = turn.runtime
        let task = Task<Void, Never> {
            await self.performTurn(turnRuntime, lease: lease) { userMessage, conversation in
                try await self.runtime.routeStructuredTurn(
                    userMessage: userMessage,
                    turnRuntime: turnRuntime,
                    validation: validation,
                    conversation: conversation,
                )
            }
        }
        // Same ordering as `startAssistantTurn`: the caller-owned `Turn` is still alive in
        // this frame, so `onTermination` can be installed before `markRunning` without
        // opening a drop-cancellation gap.
        turnRuntime.continuation.onTermination = { _ in task.cancel() }
        let started = await turn.markRunning(task: task)
        if !started {
            task.cancel()
            _ = await task.value
            lease.end()
        }
        return task
    }
}
