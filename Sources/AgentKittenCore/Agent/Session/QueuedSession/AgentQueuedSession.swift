// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// FIFO wrapper around ``AgentSession``.
///
/// `AgentQueuedSession` preserves the historical queueing behavior for callers
/// that want implicit serialization. It owns a private direct session and
/// starts the next operation only after the prior one has fully completed.
public actor AgentQueuedSession: ToolApproving {
    /// Session identifier of the wrapped direct session.
    public nonisolated let sessionID: AgentSessionID

    /// Agent identifier of the wrapped direct session.
    public nonisolated let agentID: AgentID

    /// Owner identifier of the wrapped direct session.
    public nonisolated let ownerID: UserID

    /// Durable trace shared with the wrapped direct session.
    public nonisolated let trace: AgentTrace

    /// Session-state access shared with the wrapped direct session.
    public nonisolated let state: AgentSession.SessionStateAccess

    private let session: AgentSession

    private var queue = TurnQueue()

    init(session: AgentSession) {
        self.sessionID = session.sessionID
        self.agentID = session.agentID
        self.ownerID = session.ownerID
        self.trace = session.trace
        self.state = session.state
        self.session = session
    }

    /// Current automatic compaction policy.
    public var automaticCompactionPolicy: AutomaticCompactionPolicy {
        get async { await session.automaticCompactionPolicy }
    }

    /// Updates automatic compaction policy immediately on the wrapped session.
    public func setAutomaticCompactionPolicy(_ policy: AutomaticCompactionPolicy) async {
        await session.setAutomaticCompactionPolicy(policy)
    }

    /// Approves a pending tool call.
    public func approve(callID: ToolCallID) async throws {
        try await session.approve(callID: callID)
    }

    /// Denies a pending tool call.
    public func deny(callID: ToolCallID, reason: String) async throws {
        try await session.deny(callID: callID, reason: reason)
    }

    /// Queues a text turn and returns its handle immediately.
    public func send(
        _ text: String,
        userID: UserID? = nil,
        validation: ValidationConfiguration<AssistantMessage> = .disabled,
    ) async -> Turn<AssistantMessage> {
        await send(
            text,
            userID: userID,
            turnOverrides: .init(),
            validation: validation,
        )
    }

    /// Queues a text turn with explicit configuration and returns its handle immediately.
    public func send(
        _ text: String,
        userID: UserID? = nil,
        turnOverrides: TurnOverrides,
        validation: ValidationConfiguration<AssistantMessage> = .disabled,
    ) async -> Turn<AssistantMessage> {
        let turn = await session.makeAssistantTurn(
            text,
            userID: userID,
            turnOverrides: turnOverrides,
        )
        enqueue(
            AnyQueuedTurn(
                id: turn.id,
                isCancelled: { [weak turn] in
                    guard let turn else { return true }
                    return await turn.isCancelled
                },
                markRunning: { _ in true },
                performWork: { [weak self, weak turn] in
                    guard let self else { return }
                    if let task = await self.startQueuedAssistantTurn(
                        turn,
                        validation: validation,
                    ) {
                        _ = await task.value
                    }
                },
            ),
        )
        return turn
    }

    /// Queues a structured generation and returns its handle immediately.
    public func generate<Result: Codable & Sendable & JSONSchemaProviding>(
        _ prompt: String,
        userID: UserID? = nil,
        validation: ValidationConfiguration<Result> = .disabled,
    ) async -> Turn<Result> {
        await generate(
            prompt,
            userID: userID,
            turnOverrides: .init(),
            validation: validation,
        )
    }

    /// Queues a structured generation with explicit configuration and returns its handle immediately.
    public func generate<Result: Codable & Sendable & JSONSchemaProviding>(
        _ prompt: String,
        userID: UserID? = nil,
        turnOverrides: TurnOverrides,
        validation: ValidationConfiguration<Result> = .disabled,
    ) async -> Turn<Result> {
        let turn: Turn<Result> = await session.makeStructuredTurn(
            prompt,
            userID: userID,
            turnOverrides: turnOverrides,
        )
        enqueue(
            AnyQueuedTurn(
                id: turn.id,
                isCancelled: { [weak turn] in
                    guard let turn else { return true }
                    return await turn.isCancelled
                },
                markRunning: { _ in true },
                performWork: { [weak self, weak turn] in
                    guard let self else { return }
                    if let task = await self.startQueuedStructuredTurn(
                        turn,
                        validation: validation,
                    ) {
                        _ = await task.value
                    }
                },
            ),
        )
        return turn
    }

    /// Queues a context clear.
    public func clearContext(
        state statePolicy: AgentSession.StateClearPolicy = .clear,
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(
                AnyQueuedTurn(
                    id: .generate(),
                    isCancelled: { false },
                    markRunning: { _ in true },
                    performWork: { [weak self] in
                        guard let self else {
                            continuation.resume()
                            return
                        }
                        do {
                            try await self.session.clearContext(state: statePolicy)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    },
                ),
            )
        }
    }

    /// Queues a manual context compaction.
    public func compactContext(
        _ options: ContextCompactionOptions = .init(),
    ) async throws -> ContextCompactionResult {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(
                AnyQueuedTurn(
                    id: .generate(),
                    isCancelled: { false },
                    markRunning: { _ in true },
                    performWork: { [weak self] in
                        guard let self else {
                            continuation.resume(returning: .skipped(.sessionReleased))
                            return
                        }
                        do {
                            let result = try await self.session.compactContext(options)
                            continuation.resume(returning: result)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    },
                ),
            )
        }
    }

    /// Queues a context-usage read.
    public func contextUsage() async throws -> ContextUsage {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(
                AnyQueuedTurn(
                    id: .generate(),
                    isCancelled: { false },
                    markRunning: { _ in true },
                    performWork: { [weak self] in
                        guard let self else {
                            continuation.resume(throwing: AgentSessionError.noActiveConversation)
                            return
                        }
                        do {
                            let usage = try await self.session.contextUsage()
                            continuation.resume(returning: usage)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    },
                ),
            )
        }
    }

    private func enqueue(_ item: AnyQueuedTurn) {
        queue.enqueue(item)
        if !queue.hasProcessorTask {
            queue.setProcessorTask(Task { await self.processTurnQueue() })
        }
    }

    private func processTurnQueue() async {
        while let turn = queue.nextPendingTurn() {
            guard await !turn.isCancelled else {
                continue
            }
            let genTask = Task<Void, Never> { await turn.performWork() }
            let started = await turn.markRunning(task: genTask)
            guard started else {
                genTask.cancel()
                _ = await genTask.value
                continue
            }
            _ = await genTask.value
        }
        queue.setProcessorTask(nil)
    }
}

extension AgentQueuedSession {
    private func startQueuedAssistantTurn(
        _ turn: Turn<AssistantMessage>?,
        validation: ValidationConfiguration<AssistantMessage>,
    ) async -> Task<Void, Never>? {
        guard let turn else {
            return nil
        }
        do {
            return try await session.startAssistantTurn(
                turn,
                validation: validation,
                operation: .run,
            )
        } catch is CancellationError {
            turn.continuation.finish()
            return nil
        } catch {
            turn.continuation.finish(throwing: error)
            return nil
        }
    }

    private func startQueuedStructuredTurn<Result: Codable & Sendable & JSONSchemaProviding>(
        _ turn: Turn<Result>?,
        validation: ValidationConfiguration<Result>,
    ) async -> Task<Void, Never>? {
        guard let turn else {
            return nil
        }
        do {
            return try await session.startStructuredTurn(
                turn,
                validation: validation,
                operation: .generate,
            )
        } catch is CancellationError {
            turn.continuation.finish()
            return nil
        } catch {
            turn.continuation.finish(throwing: error)
            return nil
        }
    }
}
