// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct TurnEventSink<Result: Sendable> {
    enum Output {
        case toolsOnly
        case all
    }

    private let continuation: AsyncThrowingStream<AgentEvent<Result>, Error>.Continuation
    private var mapper: ConversationEventMapper<Result>

    init(
        continuation: AsyncThrowingStream<AgentEvent<Result>, Error>.Continuation,
        agentID: AgentID,
        sessionID: AgentSessionID,
        invocationID: InvocationID
    ) {
        self.continuation = continuation
        self.mapper = ConversationEventMapper<Result>(
            agentID: agentID,
            sessionID: sessionID,
            invocationID: invocationID
        )
    }

    mutating func emit(_ event: ConversationEvent<Result>) {
        guard let agentEvent = mapper.map(event) else {
            return
        }
        continuation.yield(agentEvent)
    }

    mutating func emitIfVisible(_ event: ConversationEvent<Result>, output: Output) {
        switch output {
        case .toolsOnly:
            switch event.kind {
            case .toolCallStarted, .toolApprovalRequired, .toolCallCompleted:
                emit(event)
            case .textDelta, .result, .toolHookFired:
                break
            }
        case .all:
            emit(event)
        }
    }

    mutating func emitResult(_ result: Result, timestamp: Date) {
        continuation.yield(mapper.makeResultEvent(result, timestamp: timestamp))
    }
}
