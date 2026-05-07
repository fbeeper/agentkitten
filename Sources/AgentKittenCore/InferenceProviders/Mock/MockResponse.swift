// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A canned response item for ``MockInferenceProvider``.
public enum MockResponse: Sendable {
    /// Streams the given text word-by-word with a small artificial delay.
    case success(String)
    /// Immediately throws the given error, simulating a provider failure.
    case failure(InferenceError)
    /// Simulates a tool call followed by a text response.
    ///
    /// The mock session emits ``InferenceEvent/toolCallRequested(id:name:argumentsJSON:)``,
    /// then runs the registered tool through ``ToolExecutor`` (enforcing policy before
    /// execution). On success it emits ``InferenceEvent/toolCallCompleted(id:name:outcome:)``
    /// with the real tool result content; on denial or failure it emits
    /// ``InferenceEvent/toolCallFailed(id:name:error:)``. Either way, `thenRespond` is
    /// streamed word-by-word as the scripted model continuation.
    ///
    /// Register matching tools on ``Agent`` so the executor can find and run them.
    ///
    /// - Parameters:
    ///   - name: The tool name the model is requesting.
    ///   - argumentsJSON: The argument payload passed to the registered tool.
    ///   - thenRespond: The assistant text to stream after the tool interaction.
    case toolCall(name: String, argumentsJSON: String, thenRespond: String)
}
