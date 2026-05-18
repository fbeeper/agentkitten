// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Translates an `InferenceEvent` stream into `ConversationEvent`s for a single turn.
///
/// `InferenceDigester` is a value type; actor isolation is provided by the owning
/// actor (currently `Conversation`). Accumulates ``GenerationState`` per digest call.
struct InferenceDigester: Sendable {
    /// Iterates an unstructured inference stream and emits
    /// `ConversationEvent<AssistantMessage>` values, including the terminal result.
    func digest<S: AsyncSequence & Sendable>(
        stream: S,
        continuation: AsyncThrowingStream<ConversationEvent<AssistantMessage>, Error>.Continuation,
        conversationID: ConversationID,
    ) async throws where S.Element == InferenceEvent<String> {
        var state = GenerationState()
        try await consumeInferenceEvents(stream: stream) { event in
            switch event {
            case .delta(let chunk):
                emitTextDelta(
                    chunk,
                    continuation: continuation,
                    conversationID: conversationID,
                    state: &state,
                )

            case .toolCallRequested(let id, let name, let argumentsJSON):
                emitToolCallStarted(
                    id: id,
                    name: name,
                    argumentsJSON: argumentsJSON,
                    continuation: continuation,
                    conversationID: conversationID,
                    state: &state,
                )

            case .toolApprovalRequired(let call):
                try emitToolApprovalRequired(
                    call: call,
                    continuation: continuation,
                    conversationID: conversationID,
                    state: &state,
                )

            case .toolCallCompleted(let id, let name, let outcome):
                emitToolCallCompleted(
                    id: id,
                    name: name,
                    outcome: outcome,
                    continuation: continuation,
                    conversationID: conversationID,
                    state: &state,
                )

            case .toolHookFired(let info):
                emitToolHookFired(info, continuation: continuation, conversationID: conversationID, state: state)

            case .result(let fullText, _):
                state.fullText = fullText
                emitResult(
                    AssistantMessage(text: fullText),
                    continuation: continuation,
                    conversationID: conversationID,
                )
            }
        }
    }

    /// Iterates a structured inference stream and emits `ConversationEvent<T>`
    /// values, including the terminal result.
    func digestStructured<S: AsyncSequence & Sendable, T: Sendable>(
        stream: S,
        continuation: AsyncThrowingStream<ConversationEvent<T>, Error>.Continuation,
        conversationID: ConversationID,
    ) async throws where S.Element == InferenceEvent<T> {
        var state = GenerationState()
        try await consumeInferenceEvents(stream: stream) { event in
            switch event {
            case .delta(let chunk):
                emitTextDelta(
                    chunk,
                    continuation: continuation,
                    conversationID: conversationID,
                    state: &state,
                )

            case .toolCallRequested(let id, let name, let argumentsJSON):
                emitToolCallStarted(
                    id: id,
                    name: name,
                    argumentsJSON: argumentsJSON,
                    continuation: continuation,
                    conversationID: conversationID,
                    state: &state,
                )

            case .toolApprovalRequired(let call):
                try emitToolApprovalRequired(
                    call: call,
                    continuation: continuation,
                    conversationID: conversationID,
                    state: &state,
                )

            case .toolCallCompleted(let id, let name, let outcome):
                emitToolCallCompleted(
                    id: id,
                    name: name,
                    outcome: outcome,
                    continuation: continuation,
                    conversationID: conversationID,
                    state: &state,
                )

            case .toolHookFired(let info):
                emitToolHookFired(info, continuation: continuation, conversationID: conversationID, state: state)

            case .result(let structured, _):
                emitResult(
                    structured,
                    continuation: continuation,
                    conversationID: conversationID,
                )
            }
        }
    }

    // MARK: - Private helpers

    private func emitTextDelta<T: Sendable>(
        _ chunk: String,
        continuation: AsyncThrowingStream<ConversationEvent<T>, Error>.Continuation,
        conversationID: ConversationID,
        state: inout GenerationState,
    ) {
        state.fullText += chunk
        yieldEvent(
            kind: .textDelta(chunk),
            continuation: continuation,
            conversationID: conversationID,
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func emitToolCallStarted<T: Sendable>(
        id: ToolCallID,
        name: String,
        argumentsJSON: String,
        continuation: AsyncThrowingStream<ConversationEvent<T>, Error>.Continuation,
        conversationID: ConversationID,
        state: inout GenerationState,
    ) {
        let eventID = EventID.generate()
        state.toolStartEventIDs[id] = eventID
        yieldEvent(
            kind: .toolCallStarted(name: name, id: id, argumentsJSON: argumentsJSON),
            continuation: continuation,
            conversationID: conversationID,
            eventID: eventID,
        )
    }

    private func emitToolApprovalRequired<T: Sendable>(
        call: PendingToolCall,
        continuation: AsyncThrowingStream<ConversationEvent<T>, Error>.Continuation,
        conversationID: ConversationID,
        state: inout GenerationState,
    ) throws {
        guard let parentEventID = state.toolStartEventIDs[call.id] else {
            throw InferenceDigesterError.invalidToolApprovalSequence(callID: call.id)
        }
        yieldEvent(
            kind: .toolApprovalRequired(call: call),
            continuation: continuation,
            conversationID: conversationID,
            parentEventID: parentEventID,
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func emitToolCallCompleted<T: Sendable>(
        id: ToolCallID,
        name: String,
        outcome: ToolCallOutcome,
        continuation: AsyncThrowingStream<ConversationEvent<T>, Error>.Continuation,
        conversationID: ConversationID,
        state: inout GenerationState,
    ) {
        let parentEventID = state.toolStartEventIDs[id]
        yieldEvent(
            kind: .toolCallCompleted(name: name, id: id, outcome: outcome),
            continuation: continuation,
            conversationID: conversationID,
            parentEventID: parentEventID,
        )
        state.toolStartEventIDs[id] = nil
    }

    private func emitResult<T: Sendable>(
        _ result: T,
        continuation: AsyncThrowingStream<ConversationEvent<T>, Error>.Continuation,
        conversationID: ConversationID,
    ) {
        yieldEvent(
            kind: .result(result),
            continuation: continuation,
            conversationID: conversationID,
        )
    }

    private func emitToolHookFired<T: Sendable>(
        _ info: ToolHookInvocationInfo,
        continuation: AsyncThrowingStream<ConversationEvent<T>, Error>.Continuation,
        conversationID: ConversationID,
        state: GenerationState,
    ) {
        yieldEvent(
            kind: .toolHookFired(info),
            continuation: continuation,
            conversationID: conversationID,
            parentEventID: state.toolStartEventIDs[info.callID],
        )
    }

    private func consumeInferenceEvents<S: AsyncSequence & Sendable, T: Sendable>(
        stream: S,
        handleEvent: (InferenceEvent<T>) async throws -> Void,
    ) async throws where S.Element == InferenceEvent<T> {
        // Future: per-tool step counters (e.g. cap web-search independently of time-lookup).
        var sawResult = false
        for try await event in stream {
            try Task.checkCancellation()
            try await handleEvent(event)
            if case .result = event {
                sawResult = true
                break
            }
        }
        try Task.checkCancellation()
        if !sawResult {
            throw InferenceDigesterError.missingResult
        }
    }

    /// Creates and yields the event in one step so the timestamp is captured
    /// exactly at emission, not at some earlier construction site.
    private func yieldEvent<T: Sendable>(
        kind: ConversationEvent<T>.Kind,
        continuation: AsyncThrowingStream<ConversationEvent<T>, Error>.Continuation,
        conversationID: ConversationID,
        eventID: EventID = .generate(),
        parentEventID: EventID? = nil,
    ) {
        continuation.yield(ConversationEvent(
            kind: kind,
            metadata: ConversationEvent<T>.Metadata(
                eventID: eventID,
                conversationID: conversationID,
                timestamp: Date(),
                parentEventID: parentEventID,
            ),
        ))
    }
}

extension InferenceDigester {
    struct GenerationState {
        var fullText = ""
        var toolStartEventIDs: [ToolCallID: EventID] = [:]
    }
}

private enum InferenceDigesterError: Error {
    case missingResult
    case invalidToolApprovalSequence(callID: ToolCallID)
}
