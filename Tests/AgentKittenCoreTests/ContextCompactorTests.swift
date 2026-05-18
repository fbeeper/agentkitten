// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Test func contextCompactor_callsRequestSummaryWithRenderedEntries() async throws {
    let strategy = SummarizationContextCompactionStrategy(options: .init())
    let recorder = PromptRecorder()

    let summary = try await strategy.summarize(
        entries: [
            RenderedSessionEntry(isTurnStart: true, rendered: "User: one"),
            RenderedSessionEntry(isTurnStart: false, rendered: "Assistant: two"),
        ],
        requestSummary: { prompt in
            await recorder.record(prompt)
            return "single summary"
        },
    )

    let prompts = await recorder.all()
    #expect(summary == "single summary")
    #expect(prompts.count == 1)
    #expect(prompts[0].contains("User: one"))
    #expect(prompts[0].contains("Assistant: two"))
}

@Test func contextCompactor_splitsEntriesAfterTooLargeError() async throws {
    let strategy = SummarizationContextCompactionStrategy(options: .init())
    let counter = CallCounter()

    // Two turns: [u1, r1] and [u2, r2]. Throw inputTooLarge when both turns present.
    let entries = [
        RenderedSessionEntry(isTurnStart: true, rendered: "u1"),
        RenderedSessionEntry(isTurnStart: false, rendered: "r1"),
        RenderedSessionEntry(isTurnStart: true, rendered: "u2"),
        RenderedSessionEntry(isTurnStart: false, rendered: "r2"),
    ]

    let summary = try await strategy.summarize(
        entries: entries,
        requestSummary: { prompt in
            await counter.increment()
            if prompt.contains("u1"), prompt.contains("u2") {
                throw InferenceError.contextWindowExceeded(.init(message: "too large"))
            }
            if prompt.contains("u1") { return "summary-one" }
            return "summary-two"
        },
    )

    #expect(await counter.value == 3)
    #expect(summary == "summary-two")
}

@Test func contextCompactor_foldsNewerEntriesIntoOlderSummary() async throws {
    let strategy = SummarizationContextCompactionStrategy(options: .init())
    let counter = CallCounter()

    // Three single-entry turns, each too large to batch with another.
    let entries = [
        RenderedSessionEntry(isTurnStart: true, rendered: "A"),
        RenderedSessionEntry(isTurnStart: true, rendered: "B"),
        RenderedSessionEntry(isTurnStart: true, rendered: "C"),
    ]

    _ = try await strategy.summarize(
        entries: entries,
        requestSummary: { prompt in
            await counter.increment()
            // Fail on any multi-turn batch that doesn't contain an existing summary
            let hasExistingSummary = prompt.contains("[Conversation summary]")
            let entryCount = ["A", "B", "C"].count(where: { prompt.contains($0) })
            if entryCount > 1, !hasExistingSummary {
                throw InferenceError.contextWindowExceeded(.init(message: "too large"))
            }
            return "summary"
        },
    )

    // At minimum: 1 initial (fails) + 1 for A + 1 fold(A+B) + 1 fold((A+B)+C)
    #expect(await counter.value >= 4)
}

@Test func contextCompactor_doesNotSplitFatalErrors() async throws {
    let strategy = SummarizationContextCompactionStrategy(options: .init())
    let counter = CallCounter()

    do {
        _ = try await strategy.summarize(
            entries: [
                RenderedSessionEntry(isTurnStart: true, rendered: "User: one"),
                RenderedSessionEntry(isTurnStart: true, rendered: "User: two"),
            ],
            requestSummary: { _ in
                await counter.increment()
                throw CompactionTestError.fatal
            },
        )
        Issue.record("Expected fatal error")
    } catch CompactionTestError.fatal {
        #expect(await counter.value == 1)
    }
}

@Test func contextCompactor_doesNotSplitWhenAllowsSplittingIsFalse() async throws {
    let strategy = SummarizationContextCompactionStrategy(options: .init(allowsSplitting: false))
    do {
        _ = try await strategy.summarize(
            entries: [
                RenderedSessionEntry(isTurnStart: true, rendered: "User: one"),
                RenderedSessionEntry(isTurnStart: true, rendered: "User: two"),
            ],
            requestSummary: { _ in throw InferenceError.contextWindowExceeded(.init(message: "too large")) },
        )
        Issue.record("Expected contextWindowExceeded")
    } catch is InferenceError {}
}

@Test func contextCompactor_splitRespectsGroupBoundaries() async throws {
    // Two turns: [u1, r1] and [u2, r2]. Split must fall on the turn boundary.
    let strategy = SummarizationContextCompactionStrategy(options: .init())
    let counter = CallCounter()

    let entries = [
        RenderedSessionEntry(isTurnStart: true, rendered: "u1"),
        RenderedSessionEntry(isTurnStart: false, rendered: "r1"),
        RenderedSessionEntry(isTurnStart: true, rendered: "u2"),
        RenderedSessionEntry(isTurnStart: false, rendered: "r2"),
    ]

    let summary = try await strategy.summarize(
        entries: entries,
        requestSummary: { prompt in
            await counter.increment()
            if prompt.contains("u1"), prompt.contains("u2") {
                throw InferenceError.contextWindowExceeded(.init(message: "too large"))
            }
            if prompt.contains("u1") { return "summary-turn1" }
            return "summary-turn2"
        },
    )

    #expect(await counter.value == 3)
    #expect(summary == "summary-turn2")
}

@Test func contextCompactor_imbalancedTurnGroupsAtNextTurnStart() async throws {
    // Two prompts with no responses — each closes as its own group.
    // Rendered strings are deliberately different from summary return values
    // so that fold prompts (which include the prior summary) don't accidentally
    // match the "both raw entries present" condition.
    let strategy = SummarizationContextCompactionStrategy(options: .init())
    let counter = CallCounter()

    let entries = [
        RenderedSessionEntry(isTurnStart: true, rendered: "PROMPT_ALPHA"),
        RenderedSessionEntry(isTurnStart: true, rendered: "PROMPT_BETA"),
    ]

    let summary = try await strategy.summarize(
        entries: entries,
        requestSummary: { prompt in
            await counter.increment()
            if prompt.contains("PROMPT_ALPHA"), prompt.contains("PROMPT_BETA") {
                throw InferenceError.contextWindowExceeded(.init(message: "too large"))
            }
            if prompt.contains("PROMPT_ALPHA") { return "SUM_ALPHA" }
            return "SUM_ALPHA_BETA"
        },
    )

    #expect(await counter.value == 3)
    #expect(summary == "SUM_ALPHA_BETA")
}

@Test func contextCompactor_truncationStrategySkipsSummaryGeneration() async {
    let compactor = ContextCompactor()
    let session = TestContextCompactableSession()
    let result = await compactor.compact(
        session,
        options: .truncate(.init(preservedRecentTurnCount: 1)),
        summaryGenerator: { _ in
            Issue.record("Summary generator should not be called for truncation")
            return "unused"
        },
    )

    #expect(result.didCompact)
    let applied = await session.appliedCompactions()
    #expect(applied == [.init(summary: nil, preservedRecentTurnCount: 1)])
}

@Test func contextCompactor_customStrategyUsesSuppliedImplementation() async {
    let compactor = ContextCompactor()
    let session = TestContextCompactableSession()
    let strategy = AnyContextCompactionStrategy(id: "custom-test") { session, summaryGenerator in
        let summary = try await summaryGenerator("custom prompt")
        return try await session.applyCompaction(
            summary: summary,
            preservedRecentTurnCount: 0,
        )
    }

    let result = await compactor.compact(
        session,
        options: .custom(strategy),
        summaryGenerator: { prompt in
            #expect(prompt == "custom prompt")
            return "custom summary"
        },
    )

    #expect(result.didCompact)
    let applied = await session.appliedCompactions()
    #expect(applied == [.init(summary: "custom summary", preservedRecentTurnCount: 0)])
}

private enum CompactionTestError: Error {
    case fatal
}

private actor PromptRecorder {
    private var prompts: [String] = []
    func record(_ prompt: String) {
        prompts.append(prompt)
    }

    func all() -> [String] {
        prompts
    }
}

private actor CallCounter {
    private(set) var value = 0
    func increment() {
        value += 1
    }
}

private actor TestContextCompactableSession: ContextCompactableSession {
    struct AppliedCompaction: Equatable {
        let summary: String?
        let preservedRecentTurnCount: Int
    }

    private var applied: [AppliedCompaction] = []

    func compactionEntries() -> [RenderedSessionEntry] {
        [
            RenderedSessionEntry(isTurnStart: true, rendered: "user: one"),
            RenderedSessionEntry(isTurnStart: false, rendered: "assistant: two"),
        ]
    }

    func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int,
    ) async throws -> ContextCompactionResult {
        applied.append(.init(
            summary: summary,
            preservedRecentTurnCount: preservedRecentTurnCount,
        ))
        return .compacted(.init(
            usageBefore: ContextUsage(contextTokens: 90, contextSize: 100),
            usageAfter: ContextUsage(contextTokens: 10, contextSize: 100),
        ))
    }

    func appliedCompactions() -> [AppliedCompaction] {
        applied
    }
}
