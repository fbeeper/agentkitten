// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore

/// Forwards ``InferenceEvent`` values from ``AppleBridgedTool`` instances to the
/// active stream continuation of the owning ``AppleInferenceSession``.
///
/// One relay is created per session and shared with all bridged tools. Before each
/// generation turn ``AppleInferenceSession`` calls ``beginTurn(_:)`` to wire in
/// the current continuation; it ends that
/// relay turn again when the generation turn ends. Tool events
/// emitted during ``AppleBridgedTool/call(arguments:)`` are forwarded in real time
/// rather than post-hoc via trace scanning.
@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
actor ToolEventRelay {
    private var activeTurn: ToolEventRelayTurn?

    /// Starts forwarding events to an unstructured inference stream.
    func beginTurn(_ continuation: InferenceStream.Continuation) -> ToolEventRelayTurn {
        let turn = ToolEventRelayTurn(
            destination: .inference(continuation),
            emitRequested: { id, name, argumentsJSON in
                continuation.yield(.toolCallRequested(id: id, name: name, argumentsJSON: argumentsJSON))
            },
            emitApprovalRequired: { call in
                continuation.yield(.toolApprovalRequired(call: call))
            },
            emitCompleted: { id, name, outcome in
                continuation.yield(.toolCallCompleted(id: id, name: name, outcome: outcome))
            },
            emitHookFired: { info in
                continuation.yield(.toolHookFired(info))
            }
        )
        activeTurn = turn
        return turn
    }

    /// Starts forwarding events to a structured inference stream.
    func beginTurn<T: Sendable>(
        _ continuation: StructuredInferenceStream<T>.Continuation
    ) -> ToolEventRelayTurn {
        let turn = ToolEventRelayTurn(
            destination: .structured,
            emitRequested: { id, name, argumentsJSON in
                continuation.yield(.toolCallRequested(id: id, name: name, argumentsJSON: argumentsJSON))
            },
            emitApprovalRequired: { call in
                continuation.yield(.toolApprovalRequired(call: call))
            },
            emitCompleted: { id, name, outcome in
                continuation.yield(.toolCallCompleted(id: id, name: name, outcome: outcome))
            },
            emitHookFired: { info in
                continuation.yield(.toolHookFired(info))
            }
        )
        activeTurn = turn
        return turn
    }

    /// Stops forwarding only if `turn` is still the active relay turn.
    func endTurn(_ turn: ToolEventRelayTurn) {
        guard activeTurn === turn else {
            return
        }
        activeTurn = nil
    }

    func emitRequested(id: ToolCallID, name: String, argumentsJSON: String) {
        activeTurn?.emitRequested(id, name, argumentsJSON)
    }

    func emitApprovalRequired(call: PendingToolCall) {
        activeTurn?.emitApprovalRequired(call)
    }

    func emitCompleted(id: ToolCallID, name: String, outcome: ToolCallOutcome) {
        activeTurn?.emitCompleted(id, name, outcome)
    }

    func emitHookFired(_ info: ToolHookInvocationInfo) {
        activeTurn?.emitHookFired(info)
    }

    /// Yields `event` to the active unstructured continuation, if one is set.
    func emit(_ event: InferenceEvent<String>) {
        guard case .inference(let continuation) = activeTurn?.destination else {
            return
        }
        continuation.yield(event)
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
final class ToolEventRelayTurn: Sendable {
    enum Destination: Sendable {
        case inference(InferenceStream.Continuation)
        case structured
    }

    let destination: Destination
    let emitRequested: @Sendable (ToolCallID, String, String) -> Void
    let emitApprovalRequired: @Sendable (PendingToolCall) -> Void
    let emitCompleted: @Sendable (ToolCallID, String, ToolCallOutcome) -> Void
    let emitHookFired: @Sendable (ToolHookInvocationInfo) -> Void

    init(
        destination: Destination,
        emitRequested: @escaping @Sendable (ToolCallID, String, String) -> Void,
        emitApprovalRequired: @escaping @Sendable (PendingToolCall) -> Void,
        emitCompleted: @escaping @Sendable (ToolCallID, String, ToolCallOutcome) -> Void,
        emitHookFired: @escaping @Sendable (ToolHookInvocationInfo) -> Void
    ) {
        self.destination = destination
        self.emitRequested = emitRequested
        self.emitApprovalRequired = emitApprovalRequired
        self.emitCompleted = emitCompleted
        self.emitHookFired = emitHookFired
    }
}

#endif
