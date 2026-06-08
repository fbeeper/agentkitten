# Step 2

Tool calling

Time to drop the `preflight` rejection and implement the core of the agentic loop.

## Bridge tools to the wire format

Convert each registered `AnyAgentTool` to the provider's tool schema, injecting the rationale field the framework
expects: `OpenAIToolBridge.swift`:

```swift
static func openAITool(from tool: AnyAgentTool, rationaleDescription: String) -> OpenAITool {
    OpenAITool(
        type: "function",
        function: .init(
            name: tool.name,
            description: tool.description,
            parameters: InferenceProviderJSONValue.injectingRationale(
                into: InferenceProviderJSONValue.encoding(tool.schema.parameters),
                description: rationaleDescription,
            ),
        ),
    )
}
```

Note the session bridges its tools once at init from `toolRuntime.allTools`, then filters per request by
`parameters.toolSelection.allows(toolName:)`.

## Drive the loop

The session re-posts the full history until the model stops asking for tools. `OpenAIInferenceSession.swift`:

```swift
repeat {
    try Task.checkCancellation()
    guard await toolTurnRuntime.prepareRound() else { break } // step budget
    let outcome = try await runSingleRequest(/* streams events, appends to turnHistory */)
    stopReason = outcome.stopReason
    hasToolCalls = outcome.hasToolCalls
    await toolTurnRuntime.recordRound()
} while hasToolCalls
```

Only treat pending calls as executable when the model finishes with `"tool_calls"` — a `length` finish may carry
partial deltas that must be discarded.

### Emit paired events through ToolRuntime

Never execute tools yourself. Hand each call to the `ToolTurnRuntime` (approvals, hooks, policy, and the trace all live
behind it) and emit the matching events. `OpenAIInferenceSession+Tools.swift`:

```swift
emit(.toolCallRequested(id: callID, name: call.name, argumentsJSON: argsJSON))
let outcome = await toolTurnRuntime.invoke(
    pending,
    onApprovalRequired: { emit(.toolApprovalRequired(call: $0)) },
    onHookFired: { emit(.toolHookFired($0)) },
)
// ...
emit(.toolCallCompleted(id: callID, name: call.name, outcome: .success(content: content)))
```

The event ordering is a contract: every `.toolCallCompleted` (and every `.toolApprovalRequired`) must be preceded by a
matching-id `.toolCallRequested`, and `.result` must not arrive while a call is still open.

## Tests

- `OpenAIToolUseTests.swift` (the loop, step-budget exhaustion, tool selection) and
- `OpenAIToolResultEncodingTests.swift`.

> Tip: Remember `InferenceStreamValidator` is your friend to check nuanced behaviors in runtime.

## Outcome

A provider that implements the agentic loop allowing the model to execute tool calls as needed.
