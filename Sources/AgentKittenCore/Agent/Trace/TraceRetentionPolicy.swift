// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Retention policy for in-memory trace entries.
public enum TraceRetentionPolicy: Sendable, Codable, Equatable {
    /// Keep all trace entries in memory.
    case unbounded
    /// Keep only the most recent turns up to the given limit.
    case maxTurns(Int)
}
