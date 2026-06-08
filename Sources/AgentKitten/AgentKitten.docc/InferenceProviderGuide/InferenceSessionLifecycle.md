# Inference Session Lifecycle: reuse vs. rebuild

This one may be tricky, so it deserves its own section.

You may have run into  `sessionCompatibility(from:to:)`. It is meant to tells the framework whether an existing
conversation can survive a configuration change. Because OpenAI applies all configuration per request, only a provider
change forces a fresh conversation:

```swift
public nonisolated func sessionCompatibility(from current: ..., to next: ...) -> SessionCompatibility {
    current.provider != next.provider ? .replace : .reuse
}
```

The three cases are `.reuse`, `.rebuildSession`, and `.replace`. A provider that binds tools at construction time (like
Apple's on-device session) would instead return `.rebuildSession` on a tool-selection change and implement
`makeSession(continuing:)` to carry context forward. OpenAI's continuation simply copies the prior session's history:

```swift
public func makeSession(continuing session: OpenAIInferenceSession, ...) async throws -> OpenAIInferenceSession {
    let history = await session.captureHistory()
    return makeOpenAISession(systemPrompt: systemPrompt, toolRuntime: toolRuntime, initialHistory: history)
}
```

> Tip: The default `makeSession(continuing:)` *discards* state. Only opt into `.rebuildSession` if you implement real
> continuation. Otherwise you'll silently lose conversation history.
