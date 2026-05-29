# AGENTS.md - AgentKitten

Guidance for agents working in this repository. 
Communication style: telegraph; noun-phrases ok; drop grammar; min tokens.

## Project

AgentKitten - Swift library for building AI agents on Apple platforms. 
- Swift Package Manager project. 
- Early stage.

## Project Structure

Target Layering: 

- `AgentKitten` → `AgentKittenCore` → `AgentKittenMacros` 
- `AgentKittenInferenceSupport` → `AgentKittenCore`
- `AgentKittenAnthropicInference` → `AgentKittenCore` + `AgentKittenInferenceSupport`
- `AgentKittenAppleInference` → `AgentKittenCore` + `AgentKittenInferenceSupport`
- `Playground` → `AgentKitten` + `AgentKittenAnthropicInference` + `AgentKittenAppleInference`

Source Organization:

- `Package.swift` - SPM manifest.
- `Sources/`
  - `AgentKitten/` - Public umbrella. Re-exports `AgentKittenCore`. Entry: `AgentKitten.swift`.
  - `AgentKittenCore/` - Core runtime. Entry: `AgentKittenCore.swift`. 
    - `Agent/` - Agent loop, session, lifecycle.  Entry: `Agent.swift`, `AgentSession.swift`.
      - `Behavior/` - Base Agent configuration. Entry: `AgentBehavior.swift`.
      - `Compaction/` - Supporting for context compaction. Entry: `ContextCompactionOptions.swift`, `ContextCompactableSession.swift`, `ContextCompactor.swift`.
      - `Conversation/` - Utils for sourcing conversations. Entry: `ConversationProvider.swift`.
      - `Event` - Agent-emmited event type. Entry: `AgentEvent.swift`.
      - `Session` - Entry: `AgentSession.swift`.
      - `SessionState`	- Framework-provided KV storage for sessions. Entry: `SessionStateConfiguration.swift`.
      - `Trace` - Auditable agent record. Entry: `AgentTrace.swift`, `AgentTraceEntry.swift`.
      - `Turn` - Entry: `Turn.swift`.
    - `Conversation/` - Message/turn/context model. Entry: `Conversation.swift`.
    - `Inference/` - Provider/sesion protocols & shared types.
    - `InferenceProviders/` - In-tree mock provider (test-only, not re-exported).
    - `Localization` - Target-specific localization utils.
    - `Tools/` - Tool protocol, registry. Entry: `AgentTool.swift`.
    - `Macros/` - `@Tool`/`@RitchTool` macro surface.
    - `Resources/` - Bundled assets (localization).
    - `Shared` - Shared types and Protocols.
    - `Validation/` - Agent output validators.
  - `AgentKittenInferenceSupport/` - Shared inference utilities.
    - `Credentials/` - Auth/token utility abstraction.
  - `AgentKittenAnthropicInference/` - Anthropic HTTP + SSE adapter. Entry: `AnthropicInferenceProvider.swift`.
  - `AgentKittenAppleInference/` - Apple Intelligence adapter. Entry: `AppleInferenceProvider.swift`.
  - `AgentKittenInferenceTestSupport` - Support for evaluation of inference providers. Entry: `InferenceStreamValidator.swift`.
  - `AgentKittenMacros/` - Swift macro plugin. Compile-time codegen for `@Tool`, `@ParameterDescription`. Entry: `Plugin.swift`, `ToolMacro.swift`.
  - `Playground/` - CLI executable. Entry: `main.swift`. Subcommands: `generate`, `chat`, `tools`, `classify`, `chicken`, `pii`, `plan-mode`.
- `Tests/`
  - `AgentKittenCoreTests/` - Covers `AgentKittenCore` (largest suite).
  - `AgentKittenInferenceSupportTests/` - Covers `AgentKittenInferenceSupport`.
  - `AgentKittenAnthropicInferenceTests/` - Covers `AgentKittenAnthropicInference`.
  - `AgentKittenAppleInferenceTests/` - Covers `AgentKittenAppleInference`.
  - `AgentKittenTests/` - Covers umbrella surface.
  - `PlaygroundTests/` - CLI harness.
- Root: `README.md`, `VISION.md`, `CONTRIBUTING.md`, `.swiftlint.yml`, `.github/` (General guidance & CI).

## Commands

- **Setup**: `make setup`
- **Build**: `make build`
- **Test**: `make test`
- **Lint**: `make lint`
- **All checks**: `make all`

## Playground

- **Run**: `swift run Playground`

## Coding Style

- Swift 6. 
- Warnings as errors.
- Swift Concurrency and Synchonization. 
  - async/await, actors only, and Mutex (if strictly necessary).
  - Structured concurrency. No Task.detached unless commented why.
  - No GCD, no Combine, no DispatchQueue, no locks.
- Prefer value types (struct/enum) for data. Actors for mutable shared state.
- Swift Testing framework (@Test, #expect), not XCTest.
- Doc comments (///) required on every public type and method.
- SwiftLint enforced via `make lint` (not a build plugin).
  - For lint failures, get the exact diagnostics first. Try avoid inferring the rule from symptoms.
  - Trailing commas in collection literals (arrays, dictionaries). Apply manually if not enforced.
  - Try avoid duplicate initializers that only restate default parameter values. Prefer one initializer with defaults unless there is a tangible semantic/convenience difference for the API.

## General Rules

- Before editing any file, read it first.
- Before modifying a function, grep for all callers.
- Research before you edit.
