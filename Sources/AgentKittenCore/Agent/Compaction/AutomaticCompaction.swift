// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Trigger used by automatic context compaction.
public enum AutomaticCompactionTrigger: Sendable, Codable, Equatable, Hashable {
    /// Compact when current context tokens reach or exceed this fraction of the model context window.
    ///
    /// A value of `0` triggers on every turn. A value greater than `1` never triggers.
    ///
    /// Requires a known context window: when the provider cannot resolve
    /// ``ContextUsage/contextSize`` (e.g. an OpenAI-compatible server with no
    /// model metadata), ``ContextUsage/fillPercent`` is `nil` and this trigger
    /// never fires. Consider``absoluteTokens(_:)`` in that case.
    case percentOfContextWindow(Double)

    /// Compact when current context tokens reach or exceed an absolute count.
    ///
    /// Unlike ``percentOfContextWindow(_:)`` this needs no context-window size, only
    /// the token count, so it keeps working against providers that cannot report a
    /// window (LM Studio or other local/remote OpenAI-compatible servers). When
    /// the count is unknown the comparison is `false`, so it never fires spuriously.
    case absoluteTokens(UInt)

    func isMet(by usage: ContextUsage) -> Bool {
        switch self {
        case .percentOfContextWindow(let percent):
            guard percent > 0 else {
                return true
            }
            guard percent <= 1 else {
                return false
            }
            return (usage.fillPercent ?? 0) >= percent
        case .absoluteTokens(let limit):
            return usage.contextTokens >= .tokens(limit)
        }
    }
}

/// Automatic context compaction behavior.
public enum AutomaticCompactionPolicy: Sendable, Equatable, Hashable {
    /// Do not compact automatically.
    case disabled
    /// Compact at the beginning of a turn when the trigger is met.
    case enabled(
        trigger: AutomaticCompactionTrigger = .percentOfContextWindow(0.8),
        options: ContextCompactionOptions = ContextCompactionOptions(),
    )
}
