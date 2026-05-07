// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A rendered text representation of a single session history entry for compaction.
///
/// Sessions wrap their native entries into this type before passing them to the
/// compaction framework. ``isTurnStart`` drives turn-boundary grouping and
/// ``rendered`` is used for prompt construction. The original native entry
/// stays with the session.
public struct RenderedSessionEntry: Sendable {
    /// Whether this entry starts a new turn (i.e., is a user message or prompt).
    public let isTurnStart: Bool
    /// A provider-rendered text representation of this entry, used in compaction prompts.
    public let rendered: String

    /// Creates a rendered session entry.
    public init(isTurnStart: Bool, rendered: String) {
        self.isTurnStart = isTurnStart
        self.rendered = rendered
    }
}
