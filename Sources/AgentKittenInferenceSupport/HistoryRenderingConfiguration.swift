// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Configuration for how inference sessions render conversation history during context compaction.
///
/// Each property controls a label or format string used when summarising prior turns
/// into a compact representation passed back to the model. All properties have
/// built-in English defaults.
public struct HistoryRenderingConfiguration: Sendable {
    /// Label prepended to conversation history entries for compaction summaries.
    public var summaryMarker = "[Conversation summary]"
    /// Role label for user turns in compaction-rendered history.
    public var userRoleLabel = "User"
    /// Role label for assistant turns in compaction-rendered history.
    public var assistantRoleLabel = "Assistant"
    /// Format string for tool call entries in compaction-rendered history.
    /// Receives one `%@` argument: the tool name.
    public var toolCallFormat = "[Tool call: %@]"
    /// Format string for tool result entries in compaction-rendered history.
    /// Receives one `%@` argument: the result body.
    public var toolResultFormat = "[Tool result: %@]"
    /// Format string for tool error entries in compaction-rendered history.
    /// Receives one `%@` argument: the error body.
    public var toolErrorFormat = "[Tool error: %@]"

    /// Creates a ``HistoryRenderingConfiguration`` with the default English values.
    public init() {}
}
