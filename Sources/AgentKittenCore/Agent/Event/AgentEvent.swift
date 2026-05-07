// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// An event emitted on ``Turn/events``.
///
/// `AgentEvent` carries stable trace metadata plus a kind describing the
/// concrete event kind. The type parameter `Result` is the final result type
/// delivered in the ``AgentEvent/Kind/result(_:)`` case.
public struct AgentEvent<Result: Sendable>: Sendable {
    /// The event's semantic kind.
    public let kind: Kind
    /// Metadata used for correlation and tracing.
    public let metadata: Metadata

    /// Creates an agent event from a kind and metadata.
    public init(kind: Kind, metadata: Metadata) {
        self.kind = kind
        self.metadata = metadata
    }
}

extension AgentEvent: Equatable where Result: Equatable {}
