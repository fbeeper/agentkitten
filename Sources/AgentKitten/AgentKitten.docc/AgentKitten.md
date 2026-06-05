# ``AgentKitten``

Swift package for building provider-agnostic AI agents.

## Overview

AgentKitten gives you standard building blocks for easily creating agents without you having to reinvent the wheel. 
And, even better, allows you to implement agents independently of the concrete inference provider you choose.

With straightforward support for:

- Runtime Tool Permissions and Hooks,
- Context Compaction,
- Session KV Store,
- Validation Loop,
- Auditable traces to debug, test, and evaluate your agents.
- and more!

## Basic Building Blocks

- ``/AgentKittenCore/InferenceProvider``: Where the agent model lives. Could be the Claude API, local Apple Intelligence 
  via Foundation Models, or your own inference model. Whether stateless or stateful, on-device or remote. You leave all 
  provider specificities behind. Pick one, swap it out at no cost to your agent implementation.
- ``/AgentKittenCore/Agent``: Your base control. Configure it with tools, set up its base behavior, and the providers it 
  may use. The agent keeps this configuration. That's all.
- ``/AgentKittenCore/AgentSession``: Start a session from your Agent. Each session is independent. Same agent, different 
  sessions. Have multi-turn conversations and run parallel threads without stepping on each other. Lightweight and 
  concurrent-safe by default.
- ``/AgentKittenCore/AgentTrace``: Every session keeps a detailed record of what happened in each turn: tool calls, 
  results, compaction events, and more. Your primary resource for debugging, testing, and evaluation.

## Customization Seams

- ``/AgentKittenCore/AgentTool``: Define what your agent can act on. Each tool is a typed, schema-described function the 
  model can invoke (API calls, file access, app integrations, you name it...). And use the 
  [`@Tool`](<doc:/AgentKittenCore/Tool(_:description:)>) macro to just wire up a Swift function with minimal boilerplate.
- ``/AgentKittenCore/ToolDefinition``: Bundle the tools the agent may invoke together with the policy and hooks that 
  govern them:
  - ``/AgentKittenCore/ToolExecutionPolicy``: Approve, deny, or suspend any tool call before it runs, based on runtime 
    context you choose.
  - ``/AgentKittenCore/ToolHook``: Transform tool inputs before execution, and reshape or sanitize results before they 
    reach the model. Hooks run in declaration order.
- ``/AgentKittenCore/AgentBehavior`` and ``/AgentKittenCore/ToolBehavior``: Set the defaults your agent starts with, 
  including the system  prompt, inference settings, and compaction policy for the agent; tool availability, step budget, 
  and model guidance for the tools.
- ``/AgentKittenCore/TurnOverrides``: Override any of the behavior defaults on a per-turn basis. Swap providers, adjust 
  inference settings, restrict tool selection, or prepend context. Also the place to thread custom typed values (via 
  ``/AgentKittenCore/ExecutionConfigurationKey`` subscript) through tool approval, hooks, and inference without coupling 
  them to your agent setup.
- ``/AgentKittenCore/Validator`` / ``/AgentKittenCore/JudgeValidator``: Define acceptance criteria for the assistant's 
  response. If validation fails, AgentKitten retries automatically with feedback. Until it passes, or a judge model 
  approves it.

## Show Me Some Code

Here's a minimal sample of a simple but powerful auto-compacting search (via tool) agent for your app:

```swift
import AgentKitten
import AgentKittenAnthropicInference

let provider = InferenceProvider.anthropic()

let toolDefinition = ToolDefinition(tools: [
    AnyAgentTool(MySearchTool()),
])

let behavior = AgentBehavior(
    systemPrompt: "You are a search assistant.",
    defaultAutomaticCompactionPolicy: .enabled(
        trigger: .percentOfContextWindow(0.5)
    )
)

let agent = Agent(
    provider: provider,
    behavior: behavior,
    toolDefinition: toolDefinition,
)

let session = agent.makeSession()
```

And you can obtain text à la chat bot:

```swift
let turn = try await session.send("Find me parks near downtown.")

for try await event in turn.events {
    if case .textDelta(let text) = event.kind {
        print(text, terminator: "")
    }
}
```

Or structured output to power your app:

```swift
let turn: Turn<[PointOfInterest]> = try await session.generate("Find me parks near downtown.")

for try await event in turn.events {
    if case .result(let pois) = event.kind {
        didLoad(pois)
    }
}
```

Changing the provider of this agent from Antropic to any other provider is as simple as:

```diff
- import AgentKittenAnthropicInference
+ import AgentKittenOpenAIInference

- let provider = InferenceProvider.anthropic()
+ let provider = InferenceProvider.openAI()
```

## Topics

### Essentials

- <doc:GettingStarted>
