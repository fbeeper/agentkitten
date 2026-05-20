// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Trigger used by automatic context compaction.
public enum AutomaticCompactionTrigger: Sendable, Codable, Equatable, Hashable {
    /// Compact when current context tokens reach or exceed this fraction of the model context window.
    ///
    /// A value of `0` triggers on every turn. A value greater than `1` never triggers.
    case percentOfContextWindow(Double)

    func isMet(by usage: ContextUsage) -> Bool {
        switch self {
        case .percentOfContextWindow(let percent):
            if percent <= 0 {
                return true
            }
            if percent > 1 {
                return false
            }
            guard let contextSize = usage.contextSize, contextSize > 0 else {
                return false
            }
            return Double(usage.contextTokens) >= Double(contextSize) * percent
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
