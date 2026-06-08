# Getting Started

How to get define your first agent and run a conversation.

## Overview

This guide walks through the minimum needed to run an agent: pick an inference provider, describe the agent's behavior, 
open a session, and stream the response.

### Add the dependency

Add AgentKitten to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fbeeper/agentkitten", from: "0.0.5"),
],
```

Then add the umbrella product and an inference provider to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "AgentKitten", package: "agentkitten"),
        .product(name: "AgentKittenAnthropicInference", package: "agentkitten"),
    ],
),
```

### Choose a provider

A provider supplies model inference:

```swift
import AgentKittenAnthropicInference

let provider = InferenceProvider.anthropic()
```

> Tip: By default, with this convenient init, Anthropic provider reads `ANTHROPIC_API_KEY` from the environment.
> You can source keys from the keychain using `KeychainAPIKeyProvider` or even define a custom source conforming to 
> `APIKeyProviding` and passing it at initialization.

> Tip: On Apple Intelligence devices you can use `AgentKittenAppleInference` for fully on-device inference instead.

### Define the agent

[Agent](../../documentation/agentkittencore/agent) pairs a provider with an
[AgentBehavior](../../documentation/agentkittencore/agentbehavior) that carries the
system prompt and runtime behavior configuration:

```swift
let agent = Agent(
    provider: provider,
    behavior: AgentBehavior(
        systemPrompt: "You are a concise, helpful assistant."
    ),
)
```

### Run a turn

Open a session with [makeSession()](<../../documentation/agentkittencore/agent/makesession()>) and call 
[send(_:userID:validation:)](<../../documentation/agentkittencore/agentsession/send(_:userid:validation:)>).
Each call returns a [Turn](../../documentation/agentkittencore/turn) whose 
`events` sequence streams the response as it is produced:

```swift
let session = agent.makeSession()
let turn = try await session.send("Summarize the Swift memory model.")

for try await event in turn.events {
    switch event.kind {
    case .textDelta(let chunk):
        print(chunk, terminator: "")
    case .result(let assistant):
        // Final assembled message, if you didn't care about the stream the deltas.
        _ = assistant.text
    default:
        break
    }
}
```

That's it. You have a running agent!

### I want more!

From here, explore:

- Tools:
  - Defining tools with [AgentTool](../../documentation/agentkittencore/agenttool) (or the [`@Tool`](<../../documentation/agentkittencore/tool(_:description:)>) macro).
  - Adding tools to your agent with [ToolDefinition](../../documentation/agentkittencore/tooldefinition).
  - Controlling the tools agentic behavior (like enablement or budget) with [ToolBehavior](../../documentation/agentkittencore/toolbehavior),
  - Or get fancy by adding tool hooks ([ToolHook](../../documentation/agentkittencore/toolhook)) to your tool definition.
- Generating structured output via [generate(_:userID:validation:)](<../../documentation/agentkittencore/agentsession/generate(_:userid:validation:)>), 
- [percentOfContextWindow(_:)](<../../documentation/agentkittencore/automaticcompactiontrigger/percentofcontextwindow(_:)>)
  enables automatic context compaction for 
  long conversations.
- Auditing the agent behavior with its [AgentTrace](../../documentation/agentkittencore/agenttrace).
- More to come!
