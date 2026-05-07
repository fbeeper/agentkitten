// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// An event produced during a streaming inference call.
///
/// Consumers iterate over an `AsyncThrowingStream<InferenceEvent<Output>, Error>` returned
/// by ``InferenceSession/send(_:configuration:)``. The stream always terminates
/// with `.result` or throws — it never hangs indefinitely.
public enum InferenceEvent<Output: Sendable>: Sendable {
    /// A chunk of text from the model's in-progress response.
    case delta(String)
    /// The model is requesting a tool invocation.
    ///
    /// The provider resolves the pending call through ``ToolRuntime`` before
    /// emitting the paired ``toolCallCompleted``.
    case toolCallRequested(id: ToolCallID, name: String, argumentsJSON: String)
    /// The model-requested tool call now requires caller approval before it may execute.
    case toolApprovalRequired(call: PendingToolCall)
    /// A tool call finished; the outcome indicates success or failure.
    ///
    /// ``Conversation`` surfaces the outcome as
    /// ``AgentEvent/Kind/toolCallCompleted(name:id:outcome:)`` and the owning
    /// ``Agent`` may persist it to trace.
    case toolCallCompleted(id: ToolCallID, name: String, outcome: ToolCallOutcome)
    /// A ``ToolHook`` fired during tool execution.
    ///
    /// Hooks fire inside ``ToolTurnRuntime``, which is provider-agnostic and has no direct
    /// path to the trace. This event rides the inference stream solely to reach
    /// ``TurnTraceSink`` — it is never surfaced to the client event stream.
    case toolHookFired(ToolHookInvocationInfo)
    /// The final result of generation and the reason the provider stopped.
    case result(Output, FinishReason)
}

/// The reason an inference stream ended normally.
public enum FinishReason: String, Sendable, Codable {
    /// The model reached a natural stopping point.
    case endTurn
    /// Generation was stopped by the `maxTokens` limit.
    case maxTokens
    /// The stream was cancelled by the caller.
    case cancelled
}
