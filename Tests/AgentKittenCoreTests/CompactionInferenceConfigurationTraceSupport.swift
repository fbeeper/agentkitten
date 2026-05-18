// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore

struct SentinelContextKey: ExecutionConfigurationKey {
    typealias Value = String
    static let defaultValue = ""
    static let domains: Set<ExecutionConfigurationDomain> = [.inference]
}

struct AnotherSentinelContextKey: ExecutionConfigurationKey {
    typealias Value = String
    static let defaultValue = ""
    static let domains: Set<ExecutionConfigurationDomain> = [.inference]
}

func firstManualContextCompaction(
    on session: AgentSession,
) async -> AgentTraceEntry.Kind.ContextCompactionInfo? {
    for entry in await session.trace.snapshot() {
        if case .contextCompaction(let info) = entry.kind, info.mode == .manual {
            return info
        }
    }
    return nil
}
