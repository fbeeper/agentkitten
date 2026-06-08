# Step 3

Structured output

Conform the session to `StructuredInferenceSession` — `OpenAIStructuredInferenceSession.swift`. Replace the Step 1
throwing stub with a real implementation:

```swift
extension OpenAIInferenceSession: StructuredInferenceSession {
    public func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String, parameters: InferenceRequestParameters,
    ) async throws -> StructuredInferenceStream<T> {
        let system = buildStructuredSystemPrompt(schemaJSON: encodeStructuredSchema(T.jsonSchema))
        // run the same agentic loop as a text turn (tools allowed), then:
        let value = try decodeStructuredValue(T.self, from: outcome.text)
        // yield .result(value, ...)
    }
}
```

The three helpers come straight from `AgentKittenInferenceSupport` (`encodeStructuredSchema`,
`buildStructuredSystemPrompt`, `decodeStructuredValue`), so the only provider-specific choice is *how* you steer the
model toward valid JSON. OpenAI provider does it with an injectable instruction string the user can override:

```swift
public static let defaultStructuredOutputInstructionFormat = """
Respond with a single valid JSON value that conforms to this schema:
%@
Output only the raw JSON value. Do not use markdown, code blocks, or backticks.
...
"""
```

`generate<T>()` is provided by a protocol extension that drains the stream and returns the final value, so you only
need to implement `generateStream`.

Two things to get right: tool calls are allowed *during* structured generation (reuse the loop), and (as of today) the
turn history used here is **not** stored on the session: Its `usage` event must not be cached against `self.history`.

## Tests

- `OpenAIStructuredSessionTests.swift` (decoding, schema injection, tools during generation, invalid-JSON handling).

## Outcome

```json
{
    "status": true,
    "outcome": "A provider that also supports structured inference output."
}
```
😉
