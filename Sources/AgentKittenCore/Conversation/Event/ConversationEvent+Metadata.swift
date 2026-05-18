// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension ConversationEvent {
    struct Metadata: Sendable, Equatable {
        let eventID: EventID
        let conversationID: ConversationID
        let timestamp: Date
        let parentEventID: EventID?

        init(
            eventID: EventID,
            conversationID: ConversationID,
            timestamp: Date,
            parentEventID: EventID? = nil,
        ) {
            self.eventID = eventID
            self.conversationID = conversationID
            self.timestamp = timestamp
            self.parentEventID = parentEventID
        }
    }
}
