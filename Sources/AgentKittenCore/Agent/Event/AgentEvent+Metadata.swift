// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Metadata attached to every ``AgentEvent``.
///
/// This data makes the event stream traceable and allows later persistence
/// layers to reconstruct per-invocation timelines and parent/child edges.
extension AgentEvent {
    public struct Metadata: Sendable, Codable, Equatable {
        /// Unique identifier for this event.
        public let eventID: EventID
        /// Identifier for the session that emitted this event.
        public let sessionID: AgentSessionID
        /// Identifier shared by all events emitted from one `send()` call.
        public let invocationID: InvocationID
        /// Who produced the event.
        public let author: EventAuthor
        /// Wall-clock time captured when the event was emitted.
        public let timestamp: Date
        /// Optional parent event for trace-tree reconstruction.
        public let parentEventID: EventID?

        /// Creates event metadata with explicit trace fields.
        public init(
            eventID: EventID,
            sessionID: AgentSessionID,
            invocationID: InvocationID,
            author: EventAuthor,
            timestamp: Date,
            parentEventID: EventID? = nil,
        ) {
            self.eventID = eventID
            self.sessionID = sessionID
            self.invocationID = invocationID
            self.author = author
            self.timestamp = timestamp
            self.parentEventID = parentEventID
        }
    }
}

/// Logical author of an ``AgentEvent``.
public enum EventAuthor: Sendable, Codable, Equatable {
    /// A user-authored event.
    case user(UserID)
    /// An agent-authored event.
    case agent(AgentID)
    /// A tool-authored event.
    case tool(String)
    /// A system-authored event.
    case system
}
