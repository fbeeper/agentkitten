# Step 0

The inert target (No public surface).

Start with foundational needs and **nothing public**. No `InferenceProviding` conformance yet. This step is
purely the wire: an HTTP client or basic SDK adaptation, the request/response model types, and an SSE parser, each with
its own tests. Reviewers can reason about its correctness in isolation, and the public API surface stays at zero.

## Outcome

A target that compiles, is fully tested, and exposes _nothing_. Safe to merge on its own.
