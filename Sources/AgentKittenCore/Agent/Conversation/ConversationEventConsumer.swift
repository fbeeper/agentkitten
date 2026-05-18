// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct ConversationEventConsumer {
    enum Output {
        case recordOnly
        case emitTools
        case emit
    }

    private enum ConsumptionError: Error {
        case missingResult
    }

    let agentID: AgentID
    let sessionID: AgentSessionID

    @discardableResult
    func consume<S: AsyncSequence, Result: Sendable & Encodable>(
        _ stream: S,
        turnRuntime: TurnRuntime<Result>,
        traceSink: TurnTraceSink,
        output: Output = .emit,
    ) async throws -> Result where S.Element == ConversationEvent<Result> {
        var result: Result?
        var eventSink = TurnEventSink<Result>(
            continuation: turnRuntime.continuation,
            agentID: agentID,
            sessionID: sessionID,
            invocationID: turnRuntime.id,
        )
        for try await event in stream {
            try Task.checkCancellation()
            await traceSink.record(event)
            switch output {
            case .recordOnly:
                break
            case .emitTools:
                eventSink.emitIfVisible(event, output: .toolsOnly)
            case .emit:
                eventSink.emitIfVisible(event, output: .all)
            }
            if case .result(let output) = event.kind {
                result = output
            }
        }
        try Task.checkCancellation()
        guard let result else {
            throw ConsumptionError.missingResult
        }
        return result
    }

    func emitResult<Result: Sendable>(
        _ result: Result,
        timestamp: Date,
        on turnRuntime: TurnRuntime<Result>,
    ) {
        var eventSink = TurnEventSink<Result>(
            continuation: turnRuntime.continuation,
            agentID: agentID,
            sessionID: sessionID,
            invocationID: turnRuntime.id,
        )
        eventSink.emitResult(
            result,
            timestamp: timestamp,
        )
    }
}
