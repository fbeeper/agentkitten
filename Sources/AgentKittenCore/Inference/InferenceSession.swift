// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Per-conversation model connection.
///
/// Each conversation holds one `InferenceSession` for its lifetime.
/// Tools, execution policy, and future approval handling are bound at session
/// creation time via the ``ToolRuntime`` passed to
/// ``InferenceProviding/makeSession(systemPrompt:toolRuntime:toolSelection:inferenceContext:)``.
///
/// **Invariants conformers must satisfy:**
/// - **Cancellation propagates:** dropping the returned stream must cancel the
///   underlying request. Implement the stream's `onTermination` to cancel the
///   backing task.
/// - **The stream terminates:** every stream must eventually yield `.result` or
///   throw — it must never hang indefinitely.
public typealias InferenceStream = AsyncThrowingStream<InferenceEvent<String>, Error>

public protocol InferenceSession: Actor {
    /// The concrete async sequence type yielded by ``run(_:parameters:)``.
    associatedtype Stream: AsyncSequence & Sendable where Stream.Element == InferenceEvent<String>

    /// Runs a single inference turn and streams the model's response.
    ///
    /// ``InferenceRequestParameters/toolSelection`` expresses the turn's
    /// tool-availability policy as resolved by `Conversation` / `AgentSession`.
    /// Providers may enforce that policy either directly in the request or by
    /// requiring a rebuilt session before the turn runs.
    ///
    /// - Parameters:
    ///   - message: The user message for this turn.
    ///   - parameters: Generation settings and tool selection for this turn.
    /// - Returns: An async sequence of ``InferenceEvent`` values.
    ///   Always ends with `.result` or an error.
    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> Stream

    /// Estimates the session's current context usage.
    ///
    /// The default implementation throws ``InferenceError/unsupportedConfiguration(_:)``.
    /// Override to provide real token counts.
    func contextUsage() async throws -> ContextUsage
}

extension InferenceSession {
    public func contextUsage() async throws -> ContextUsage {
        throw InferenceError.unsupportedConfiguration(
            "\(Self.self) does not support context usage estimation.",
        )
    }
}
