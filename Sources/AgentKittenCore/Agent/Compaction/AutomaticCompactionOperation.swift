// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

enum AutomaticCompactionOperation {
    enum Decision {
        case skip(ContextCompactionResult)
        case compact(ContextCompactionOptions)
    }

    static func decision(
        _ conversation: AnyConversation,
        policy: AutomaticCompactionPolicy,
    ) async throws -> Decision {
        let trigger: AutomaticCompactionTrigger
        let options: ContextCompactionOptions
        switch policy {
        case .disabled:
            return .skip(.skipped(.disabled))
        case .enabled(let compactionTrigger, let compactionOptions):
            trigger = compactionTrigger
            options = compactionOptions
        }

        let usage = try await conversation.contextUsage()
        guard trigger.isMet(by: usage) else {
            return .skip(.skipped(.triggerNotMet(usage)))
        }
        return .compact(options)
    }

    static func compactIfNeeded(
        _ conversation: AnyConversation,
        policy: AutomaticCompactionPolicy,
        summaryGenerator: ContextCompactionSummaryGenerator,
    ) async throws -> ContextCompactionResult {
        let decision = try await decision(conversation, policy: policy)
        switch decision {
        case .skip(let result):
            return result
        case .compact(let options):
            return try await conversation.compactContext(
                options: options,
                summaryGenerator: summaryGenerator,
            )
        }
    }

}
