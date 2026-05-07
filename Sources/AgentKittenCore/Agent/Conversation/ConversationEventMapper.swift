// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct ConversationEventMapper<Result: Sendable> {
    let agentID: AgentID
    let sessionID: AgentSessionID
    let invocationID: InvocationID

    private var toolStartEventIDs: [ToolCallID: EventID] = [:]

    init(
        agentID: AgentID,
        sessionID: AgentSessionID,
        invocationID: InvocationID
    ) {
        self.agentID = agentID
        self.sessionID = sessionID
        self.invocationID = invocationID
    }

    mutating func map(_ event: ConversationEvent<Result>) -> AgentEvent<Result>? {
        let eventID = EventID.generate()
        let kind: AgentEvent<Result>.Kind
        let parentEventID: EventID?
        let eventAuthor: EventAuthor

        switch event.kind {
        case .textDelta(let text):
            kind = .textDelta(text)
            parentEventID = nil
            eventAuthor = .agent(agentID)

        case .toolCallStarted(let name, let id, _):
            kind = .toolCallStarted(name: name, id: id)
            toolStartEventIDs[id] = eventID
            parentEventID = nil
            eventAuthor = .agent(agentID)

        case .toolApprovalRequired(let call):
            kind = .toolApprovalRequired(call: call)
            parentEventID = toolStartEventIDs[call.id]
            eventAuthor = .system

        case .toolCallCompleted(let name, let id, let outcome):
            kind = .toolCallCompleted(name: name, id: id, outcome: outcome)
            parentEventID = toolStartEventIDs[id]
            toolStartEventIDs[id] = nil
            eventAuthor = author(forToolCallNamed: name, outcome: outcome)

        case .result(let result):
            kind = .result(result)
            parentEventID = nil
            eventAuthor = .agent(agentID)

        case .toolHookFired:
            return nil
        }

        return AgentEvent<Result>(
            kind: kind,
            metadata: AgentEvent<Result>.Metadata(
                eventID: eventID,
                sessionID: sessionID,
                invocationID: invocationID,
                author: eventAuthor,
                timestamp: event.metadata.timestamp,
                parentEventID: parentEventID,
            )
        )
    }

    func makeResultEvent(_ result: Result, timestamp: Date) -> AgentEvent<Result> {
        AgentEvent(
            kind: .result(result),
            metadata: AgentEvent<Result>.Metadata(
                eventID: .generate(),
                sessionID: sessionID,
                invocationID: invocationID,
                author: .agent(agentID),
                timestamp: timestamp,
            )
        )
    }

    private func author(
        forToolCallNamed name: String,
        outcome: ToolCallOutcome
    ) -> EventAuthor {
        switch outcome {
        case .success, .failure(.execution):
            .tool(name)
        case .failure(.stepLimitExceeded), .failure(.denied):
            .system
        }
    }
}
