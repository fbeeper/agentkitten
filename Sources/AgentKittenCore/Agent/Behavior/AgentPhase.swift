// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A lifecycle phase that may use phase-specific inference behavior.
public enum AgentPhase: Sendable, Hashable {
    /// Context compaction and summarization work performed outside normal turns.
    case compaction
}
