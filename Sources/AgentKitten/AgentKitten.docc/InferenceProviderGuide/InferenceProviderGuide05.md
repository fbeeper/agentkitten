# Step 5

Context compaction

Conform the session to `ContextCompactableSession`. (`OpenAIInferenceSession+Compaction.swift`)

The framework's `ContextCompactor` reads history, runs summarization, and writes the result back through two methods.
The session never references the compactor:

```swift
extension OpenAIInferenceSession: ContextCompactableSession {
    public func compactionEntries() -> [RenderedSessionEntry] {
        history.map { RenderedSessionEntry(isTurnStart: $0.role == .user, rendered: render($0)) }
    }

    public func applyCompaction(summary: String?, preservedRecentTurnCount: Int) async throws
        -> ContextCompactionResult { /* ... */ }
}
```

`compactionEntries()` renders each wire message to labelled text using the provider's `HistoryRenderingConfiguration`
(configurable role labels and tool formats. Don't hardcode "User:" / "Assistant:"). `applyCompaction` uses
`TurnPreservationPlan` to keep the most recent N turns, optionally prepends a summary turn pair, and then **clears the
cached token count** so the next `contextUsage()` re-probes against the compacted history:

```swift
let plan = TurnPreservationPlan(entries: history,
                                preservedRecentTurnCount: preservedRecentTurnCount,
                                isTurnStart: { $0.role == .user })
history = summary.map { summaryMessages($0) + plan.recentEntries(from: history) }
       ?? plan.recentEntries(from: history)
cachedContextTokens = .unknown
```

History is guaranteed stable between `compactionEntries()` and `applyCompaction()` (both run inside the `Conversation`
operation gate), so no defensive snapshotting is needed. Return `.compacted(usageBefore:usageAfter:)`, or
`.skipped(...)` when there's nothing to compact.

## Tests

- `OpenAIContextCompactionTests.swift` (rendering, summary-preserving compaction, empty-history skip path, usage
before/after).

## Outcome

A provider that is able to perform context compaction.
