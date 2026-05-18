// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Runtime state retained by generation tasks after the caller-owned ``Turn`` handle is released.
final class TurnRuntime<Result: Sendable>: Sendable {
    let id: InvocationID
    let text: String
    let sender: UserID
    let requestedTurnOverrides: TurnOverrides
    let executionEnvironment: ExecutionEnvironment
    let rawEvents: AsyncThrowingStream<AgentEvent<Result>, Error>
    let continuation: AsyncThrowingStream<AgentEvent<Result>, Error>.Continuation

    init(
        id: InvocationID,
        text: String,
        sender: UserID,
        requestedTurnOverrides: TurnOverrides,
        executionEnvironment: ExecutionEnvironment,
    ) {
        self.id = id
        self.text = text
        self.sender = sender
        self.requestedTurnOverrides = requestedTurnOverrides
        self.executionEnvironment = executionEnvironment
        let (stream, continuation) = AsyncThrowingStream<AgentEvent<Result>, Error>.makeStream()
        self.rawEvents = stream
        self.continuation = continuation
    }
}
