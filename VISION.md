This is not an ironclad roadmap, but in its future AgentKitten may gain support features in many areas:

#### Session/Turn

- [ ] Forking AgentSession to allow clients explore branching from current session snapshot.
- [ ] Allow steering input mid turn (on clean seams like when ongoing tool execution completes).
- [ ] Token consumption reporting (input tokens, output tokens, cache hits, and therefore allow cost estimation for clients).
- [ ] More lifecycle hooks (turn start, turn end, session teardown) for easy metrics emission, triggering trace and/or transcript persistence, and other external integrations.

#### Trace

- [ ] Offering fine-tuned data retention/privacy policies for the Agent trace.
- [ ] Multi-agent traces, and trace viewer.
- [ ] Eval conveniences.

#### Prompt and Context

- [ ] Per-turn context injection hook for dynamic system prompt patching.
- [ ] Retrieval-Augmented Generation (RAG) support.

#### Inference History/Transcript

- [ ] Consider if AgentKitten should own the Inference History/Transcript. (Can power advanced operations like cross-provider continuity or branching).
- [ ] Session Persistence and Restoration. (An alternative is possible without AgentKitten-owned history).

#### Tools

- [ ] Is there need for a more formal Tool permissions model?
- [ ] Support an framework-provided "Assistant-model" Tool.
- [ ] Model Context Protocol (MCP) support. (Not really a tool, but...)
- [ ] Support Vector Databases for Tool retrieval.

#### Memory

- [ ] Framework-provided Agent-level Memory support.
- [ ] Other advanced agent/conversation memory mechanisms.

#### Agentic

- [ ] A simple linear in-agent Planning/Execution Loop to support small on-device models.
- [ ] Tool backgrounding.
- [ ] Sub-agents and Agentic Graph.

#### Convenience

- [ ] More built-in Tools and Providers.
