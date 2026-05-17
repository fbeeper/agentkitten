<p align="end">
    <picture>
        <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/fbeeper/agentkitten/main/Docs/Resources/kitten-light.svg">
        <img src="https://raw.githubusercontent.com/fbeeper/agentkitten/main/Docs/Resources/kitten-dark.svg" alt="AgentKitten" width="100">
    </picture>
</p>

[![AgentKitten on Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-Compatible-brightgreen.svg?style=flat)](https://swiftpackageindex.com/fbeeper/agentkitten)
[![Swift 6.2+](https://img.shields.io/badge/Swift-6.0+-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![iOS, macOS, visionOS, tvOS, watchOS](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-blue.svg?style=flat)](https://developer.apple.com/)
[![Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-333333.svg?style=flat)](LICENSE)

[![Build Status](https://github.com/fbeeper/agentkitten/actions/workflows/swift.yml/badge.svg)](https://github.com/fbeeper/agentkitten/actions/workflows/swift.yml)
[![Codecov Status](https://codecov.io/gh/fbeeper/agentkitten/branch/main/graph/badge.svg)](https://codecov.io/gh/fbeeper/agentkitten)
[![SPI Versions Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffbeeper%2Fagentkitten%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/fbeeper/agentkitten)
[![SPI Platforms Status](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffbeeper%2Fagentkitten%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/fbeeper/agentkitten)

# AgentKitten

Swift package for building provider-agnostic AI agents on Apple platforms.

## TLDR

AgentKitten gives you standard building blocks for easily creating agents on Apple platforms without you having to reinvent their wheels. 
And, even better, abstracted from any and all concrete provider APIs.

- Effortlessly build fully customizable and provider-agnostic AI agents.
- With straightforward support for:
  - Runtime Tool Permissions and Hooks,
  - Context Compaction,
  - Session KV Store,
  - Validation Loop,
  - and more!
- And have simple auditable traces to debug, test, and evaluate your agents.

Yes... these days you could vibe-code the entire thing every time, but why not save tokens and reduce the responsibilities of your project? 🙃

## Tell Me More

There already is a quite stable shared language of what an agent harness can do for a large language model:

- To illustrate, *Tools* are a concept that most LLM/agent provider APIs/SDKs fully support to allow a model to execute things (API calls, file operations, or any custom logic you wire up). However, there are provider specificities, and there typically isn't an standard for *execution permissions* and *hooks* at runtime.
- But there are so many more widely shared concepts that you may have to reimplement to get a powerful agent going. For example, controlling *tool availability*, obtaining *model rationale* for tool execution, performing *context compaction*, keeping *session state*, or even defining *validation loops* around the model's output.

Besides that, you may also want/need to avoid the cost of changing providers:

- During the exploratory phase of features, because you may not yet know which model performs best for your agent.
- For your production agents, because new models come out often, pricing changes, business policies evolve, and relationships change, APIs evolve...

**AgentKitten aims to help by offering simple ways (and with progressive disclosure where possible) to implement those base agent features independently of the concrete provider you choose.**

And, of course, given the stochastic nature of LLMs, AgentKitten has also considered traceability as a first-class agent feature for debugging, testing, and evaluation.

## Basic Building Blocks

`InferenceProvider`: Where the agent model lives. Could be the Claude API, local Apple Intelligence via Foundation Models, or your own inference model. Whether stateless or stateful, on-device or remote. You leave all provider specificities behind. Pick one, swap it out at no cost to your agent implementation.

`Agent`: Your base control. Configure it with tools, set up its base behavior, and the providers it may use. The agent keeps this configuration. That's all.

`AgentSession`: Start a session from your Agent. Each session is independent. Same agent, different sessions. Have multi-turn conversations and run parallel threads without stepping on each other. Lightweight and concurrent-safe by default.

`Trace`: Every session keeps a detailed record of what happened in each turn: tool calls, results, compaction events, and more. Your primary resource for debugging, testing, and evaluation.

## Customization Seams

`AgentTool`: Define what your agent can act on. Each tool is a typed, schema-described function the model can invoke (API calls, file access, app integrations, you name it...). And use the `@Tool` macro to just wire up a Swift function with minimal boilerplate.

`ToolDefinition`: Bundle the tools the agent may invoke together with the policy and hooks that govern them:
- `ToolExecutionPolicy`: Approve, deny, or suspend any tool call before it runs, based on any runtime context you choose.
- `ToolHook`: Transform tool inputs before execution, and reshape or sanitize results before they reach the model. Hooks run in declaration order.

`AgentBehavior` and `ToolBehavior`: Set the defaults your agent starts with, including the system prompt, inference settings, and compaction policy for the agent; tool availability, step budget, and model guidance for the tools.

`TurnOverrides`: Override any of those behavior defaults on a per-turn basis. Swap providers, adjust inference settings, restrict tool selection, or prepend context. Also the place to thread custom typed values (via `ExecutionConfigurationKey` subscript) through tool approval, hooks, and inference without coupling them to your agent setup.

`Validator` / `JudgeValidator`: Define acceptance criteria for the assistant's response. If validation fails, AgentKitten retries automatically with feedback. Until it passes, or a judge model approves it.

## Show Me Some Code

Here's a minimal sample of a simple but powerful auto-compacting search agent for your app:

```swift
let provider = InferenceProvider.anthropic()

let toolConfig = ToolDefinition(tools: [
    AnyAgentTool(MySearchTool()),
])

let behavior = AgentBehavior(
    systemPrompt: "You are a search assistant.",
    defaultAutomaticCompactionPolicy: .enabled(
        trigger: .percentOfContextWindow(0.5)
    )
)

let agent = Agent(
    behavior: behavior,
    provider: provider,
    toolDefinition: toolConfig,
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
let turn = try await session.generate<[PointOfInterest]>("Find me parks near downtown.")

for try await event in turn.events {
    if case .result(let pois) = event.kind {
        didLoad(pois)
    }
}
```

## What You Could Build (and some Samples)

Sky is the limit, but let me say that in 2026...

- Good old fuzzy matching and filters on your app's search bar may not feel enough to your users anymore. Today, you can let them describe what they are looking for. And your agent can put together the search parameters and filters that yield the right results. No more fiddling with pickers or having to know the almighty power-user features ahead of time.

- Your app has many settings that make it special, but your beautiful and painstakingly organized hierarchical settings are still a time consuming wall of toggles for the user. These days, an agent could be there to help your users customize 6 different features on one go with much less fuss.

- And... why not? Your app/game could have a quirky character that talks in riddles and will give you the key to the castle if you can give them the right ingredients for their dinner.

  See a toy example at `swift run Playground chicken`

Gimmicky samples aside, here are some things that are simple to reach for with AgentKitten:

- On-device models have limited context windows. But that doesn't have to limit the conversation (or send you into a custom implementation tangent). AgentKitten can compact context automatically as the session grows, so users get an infinite multi-turn experience without you managing memory manually. 
  
  Try it at `swift run Playground chat --compaction --show-usage`
  
- Giving an agent tools is powerful, but users sometimes want/need to stay in the loop. With AgentKitten you can easily let them approve or deny each tool call before it runs, and will even have the model's own rationale for why it wants to use each tool call. And you can also define custom silent non-interactive policies when human-in-the-loop isn't needed. 

  Try it at `swift run Playground chat --tool-policy ask`
  
- Some tasks benefit from a thinking phase before an acting phase. With per-turn overrides you can shift the agent into a planning mode. Restricting tools, changing guidance, then opening them back up for execution. The same pattern behind plan mode in coding harnesses. 

  Try it at `swift run Playground plan-mode`
  
- Privacy is a first-class concern for many apps. AgentKitten makes it straightforward to build a redaction contract with your users: strip sensitive data from the input, run inference, then rehydrate it right before tools execute. Thus, keeping user data entirely outside the model. 

  Try it at `swift run Playground pii`

- Because every session produces a detailed trace of Agent lifecycle (including tool calls and their results,) you can eval your agents without rebuilding the harness each time. Swap prompts, tweak scaffolding, or change providers and compare outcomes. Great for iterating quickly without the menial parts.

  Try it at `swift run Playground chat --trace`

- User-generated content is unpredictable by definition. An agent with an image-capable model and your rich tool providing it images can help your app moderate uploads before they go live, help pre-populate alt-text descriptions, or extract structured data from photos. Practical patterns for any app where users upload their own images.

  Try it at `swift run Playground tools --image-demo --provider anthropic`

## Roadmap

Before dreaming of adding more features, after its initial pre-release, the most important milestones reside on:

- [ ] Bring up documentation.
- [ ] Improve the testing suite and Playground.
- [ ] Try pursue symmetry between base Agent/Tools behavior and turn overrides (API breaking).
- [ ] Split inference providers in independent targets (API breaking).

Past that, there is a long list of possibilities to make AgentKitten better. Find an initial spill of ideas in [VISION.md](VISION.md).

## Requirements & Installation

macOS 15+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+. Swift 6.

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/fbeeper/agentkitten", from: "0.0.1")
```

Then add `"AgentKitten"` to your target's dependencies.

## Playground

The project includes playground of its functionality you can exercise:

Explore all its options with `swift run Playground --help`.

## AI Disclosure

This framework has been painstakingly designed, reviewed, and hand tested by me. But very deliberately built using AI as the writing tool. I very thoroughly steered AI coding harnesses in all things big and small to deliver a solid and human-maintainable project. A conscious exercise for the sake of a sane balance between quality and getting things done.
