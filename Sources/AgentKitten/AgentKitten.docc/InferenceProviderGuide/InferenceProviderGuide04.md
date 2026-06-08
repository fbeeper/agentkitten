# Step 4

Token counting

Override `contextUsage()` to replace the throwing default. (`OpenAIInferenceSession+Context.swift`)

This one is possibly a terrible example, but let's proceed anyway: OpenAI has no token-count endpoint for chat
completions (and I didn't want to add TikToken's dependency to guesstimate tokens!), so the session:

1. Caches the `usage` total reported in each completed turn's final chunk.
2. On a cache miss (e.g. right after compaction), fires a minimal probe request with `max_completion_tokens: 1`
   and reads only its `usage` event, leaving history untouched.
3. Resolves the context window from `/models/{id}` metadata, caching per model.

```swift
public func contextUsage() async throws -> ContextUsage {
    let lease = try operationGate.begin(.contextUsage)
    defer { lease.end() }
    return try await uncheckedContextUsage()
}
```

Note the `uncheckedContextUsage()` split: compaction (Step 5) already holds the operation gate, so it needs a variant
that doesn't re-acquire the single-flight lease.

Return type is `ContextUsage(contextTokens:contextSize:)`, both `TokenCount` values. `TokenCount` has an explicit
`.unknown` case — use it rather than guessing when a number isn't available, and let `ContextUsage.fillPercent`
(returns `nil` when either side is unknown) do the arithmetic for clients.

> Tip: Clients may have/need alternatives to overcome limitations of the provider regarding token counting.
>
> For example, they should be able to use fixed token count as an strategy for compaction (see
> `AutomaticCompactionTrigger.absoluteTokens`), and some providers may define custom keys to override context size
> (see `OpenAIContextWindowKey` as a guide).
>
> Also, for the curious... check the LM Studio API metadata fallback in the framework's Anthropic and OpenAI providers.

## Tests

- `OpenAIContextUsageTests.swift` (caching, `/models/{id}` resolution, per-turn model override).

## Outcome

A provider that can provide the client with context usage information.
