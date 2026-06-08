# Step 1

Plain text inference

Now add the public surface, but only for text. AKA, conform to 
[`InferenceProviding`](../../documentation/agentkittencore/inferenceproviding) and 
[`InferenceSession`](../../documentation/agentkittencore/inferencesession), and **gate everything else loudly.**

## The provider

`OpenAIInferenceProvider` is an actor that holds configuration and makes sessions:

```swift
public actor OpenAIInferenceProvider: InferenceProviding {
    public init(
        credentials: OpenAICredentials = .key(EnvironmentAPIKeyProvider("OPENAI_API_KEY")),
        model: String = "gpt-4o",
        baseURL: URL = OpenAIInferenceProvider.defaultBaseURL,
        // ... rendering + structured-output config, added in later steps
    )

    public nonisolated func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> OpenAIInferenceSession { /* ... */ }
}
```

`InferenceProviding` has only one required method for _text generation_: `makeSession(...)`. The rest (`preflight`,
`sessionCompatibility`, and `makeSession(continuing:)`) have sensible defaults you override as you grow.

## The session and the event stream

`OpenAIInferenceSession` is an `Actor` that owns `var history: [OpenAIMessage]` and implements `run(_:parameters:)`.
The contract for `run` is strict and worth internalising:

```swift
// InferenceSession.swift
public typealias InferenceStream = AsyncThrowingStream<InferenceEvent<String>, Error>

public protocol InferenceSession: Actor {
    associatedtype Stream: AsyncSequence & Sendable where Stream.Element == InferenceEvent<String>

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> Stream
    func contextUsage() async throws -> ContextUsage // Defaulted to throw. And we'll keep it that way until Step 4.
}
```

Two invariants the framework relies on:

1. **The stream must terminate** with `.result` or by throwing. Never hang.
2. **Cancellation must propagate**. When the consumer drops the stream, cancel the backing request.

OpenAI's `run` honours both: It spins the turn into a `Task`, and `onTermination` cancels that task and releases the
operation lease.

```swift
public func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
    let lease = try operationGate.begin(.run)
    let (stream, continuation) = InferenceStream.makeStream()
    let task = Task { await runTurn(/* ... */, continuation: continuation) }
    continuation.onTermination = { _ in
        lease.end()
        task.cancel()
    }
    return stream
}
```

For text, the only events you emit are `.delta(String)` chunks and a final `.result(text, finishReason)`.
`FinishReason` is `.endTurn` / `.maxTokens` / `.cancelled`.

## Gate everything else, loudly

This is the heart of progressive disclosure. At Step 1 the OpenAI provider deliberately refuses what it can't yet do:

- **Tools:** `preflight(...)` throws if any tool is selected.
- **Structured output:** `generateStream<T>` throws `InferenceError.unsupportedConfiguration`.
- **Token counting:** `contextUsage()` is left as the default throwing implementation.

Each gate is a one-line breadcrumb for the next PR, and a clear runtime signal to users that the capability isn't here
yet. It's better to avoid a silent surprise that leads to a lot of head scratching.

## Public factories

Give users an ergonomic entry point on the `InferenceProvider` wrapper rather than asking them to construct the actor \
directly. `InferenceProvider+OpenAI.swift`:

```swift
extension InferenceProvider where Provider == OpenAIInferenceProvider {
    public static func openAI(model: String = "gpt-4o") -> Self { /* ... */ }
    public static func openAI(credentials: some APIKeyProviding,
                              model: String = "gpt-4o",
                              baseURL: URL = OpenAIInferenceProvider.defaultBaseURL) -> Self { /* ... */ }
}
```

> Tip: Credentials in this sample provider are a small strategy enum so local servers need no key. This is not a
> framework requirement, but is nice to know if you are planning similar support. (See `OpenAICredentials.swift`.)

## Tests

- `OpenAISessionTests.swift` (streaming, history accumulation, finish reasons, errors) plus
- `OpenAIStreamConformanceTests.swift`.

**Run every raw stream through `InferenceStreamValidator.validate(_:)`** to catch contract breaches in tests instead of
in production.

## Outcome

A usable text only provider, reachable from the public API, that fails predictably on everything it doesn't support yet.
