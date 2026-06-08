# Building an Inference Provider for AgentKitten

How to build your own provider.

This guide walks through bringing a new model provider into AgentKitten the way the framework-provided OpenAI provider 
was built: one capability at a time, each step independently, useful, reviewable, and each feature gated by its own 
seam.

It uses the real [`AgentKittenOpenAIInference`](../../documentation/agentkittenopenaiinference/) target as the example. 
Every section points at the file that implements it, so you can read this as a tutorial *and* as a map of the existing 
code.

> Tip: A provider with a partial feature set (e.g. only capable of text inference) is perfectly valid if that's all you 
> need.
>
> In that case, it is preferred to avoid silently no-op an unimplemented capability. A provider that can't yet do tools 
> should *reject tools loudly*, not quietly drop them. That single discipline is what lets you ship a provider in 
> small, honest increments instead of one big effort upfront.

---

## Mental model

AgentKitten talks to models through a thin boundary. The agent loop, tool execution, approvals, tracing, and compaction 
policy all live in [`AgentKittenCore`](../../documentation/agentkittencore/). A provider only has to translate between 
that boundary and a specific model API.

Capabilities are not a single all-or-nothing conformance.

The boundary was designed to try keep **progressive disclosure** when implementing a provider (and what currently isn't 
progressive, is tracked in  [Issue #69](https://github.com/fbeeper/agentkitten/issues/69) 😉).

| Capability | Seam that unlocks it |
|---|---|
| Plain text | conform to `InferenceProviding` + `InferenceSession` |
| Tool calling | bridge `ToolRuntime` tools, drive the agentic loop, emit paired events |
| Structured output | implement the `StructuredInferenceSession` |
| Token counting | override `InferenceSession.contextUsage()` (default throws) |
| Context compaction | conform the session to `ContextCompactableSession` |
| Session rebuild | return `.rebuildSession` + implement `makeSession(continuing:)` |

You can implement only what you need. A text-only provider is a complete, shippable provider.

The two central types:

- [`InferenceProviding`](../../documentation/agentkittencore/inferenceproviding): The provider interface. Stateless, 
  `Sendable`, a factory for sessions. (`InferenceProvider.swift`)
- [`InferenceSession`](../../documentation/agentkittencore/inferencesession): Typically one per conversation, an 
  `Actor` that owns the wire history and runs turns. (`InferenceSession.swift`)

---

## Prerequisites

### Target layering

A provider is its own SPM target depending on `AgentKittenCore` (the core framework) and `AgentKittenInferenceSupport` 
(that contains shared helpers for inference targets). 

In `Package.swift`:


```swift
.target(
    name: "AgentKittenOpenAIInference",
    dependencies: ["AgentKittenCore", "AgentKittenInferenceSupport"],
),
```

Add a matching `.library` product and a `.testTarget` that also depends on `AgentKittenInferenceTestSupport` (you'll 
want its stream validator `InferenceStreamValidator`):

```swift
.testTarget(
    name: "AgentKittenOpenAIInferenceTests",
    dependencies: [
        "AgentKittenOpenAIInference",
        "AgentKittenInferenceSupport",
        "AgentKittenInferenceTestSupport",
    ],
),
```

### What AgentKittenInferenceSupport gives you for free

What this target offers publicly is evolving, the target currently provides at least:

- **History rendering config**: `HistoryRenderingConfiguration` (role labels and format strings for compaction).
- **Credentials**: 
  - The [`APIKeyProviding`](../../documentation/agentkitteninferencesupport/apikeyproviding) protocol,
  - [`EnvironmentAPIKeyProvider`](../../documentation/agentkitteninferencesupport/environmentapikeyprovider), and 
  - [`KeychainAPIKeyProvider`](../../documentation/agentkitteninferencesupport/keychainapikeyprovider).
- **Structured-output helpers**: 
  - [`decodeStructuredValue(_:from:)`](<../../documentation/agentkitteninferencesupport/decodestructuredvalue(_:from:)>),
  - [`encodeStructuredSchema(_:)`](<../../documentation/agentkitteninferencesupport/encodestructuredschema(_:)>), and
  - [`buildStructuredSystemPrompt(schemaJSON:systemPrompt:format:)`](<../../documentation/agentkitteninferencesupport/buildstructuredsystemprompt(schemajson:systemprompt:format:)>).

---

## Topics

### Guiding Steps

- <doc:InferenceProviderGuide00>
- <doc:InferenceProviderGuide01>
- <doc:InferenceProviderGuide02>
- <doc:InferenceProviderGuide03>
- <doc:InferenceProviderGuide04>
- <doc:InferenceProviderGuide05>
- <doc:InferenceSessionLifecycle>
