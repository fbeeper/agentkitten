# How to Contribute

Thanks for your interest in contributing to AgentKitten.

AgentKitten aims to make building AI agents on Apple platforms simple, reliable, 
and provider-agnostic. Contributions of all sizes are welcome — bug fixes, 
documentation improvements, tests, and new features.

## Before You Start

Before opening a pull request:

* Search existing issues and discussions.
* For substantial changes or API additions, open an issue first.
* Keep pull requests focused and scoped to a single concern.

Public API changes should be discussed before implementation.

## Development Setup

### Clone

```bash
git clone https://github.com/fbeeper/agentkitten.git
cd agentkitten
```

### Build

```bash
swift build 
```

### Run tests

```bash
swift test 
```
## Documentation

Public APIs should include documentation comments.

Update documentation when:

- Adding new APIs.
- Changing behavior.
- Introducing new concepts.

Examples are documentation too — keep them current.

## Source File Headers

Owned Swift source files in `Sources/` and `Tests/` must begin with:

```swift
// SPDX-FileCopyrightText: 2026 AgentKitten Authors and Contributors
// SPDX-License-Identifier: Apache-2.0
```

Do not add this header to `Package.swift`, resource files, manifests, docs, or
vendored/generated files unless the repository policy changes.

## Pull Requests

When opening a PR:

- Use a descriptive title.
- Explain the motivation and approach.
- Link related issues.
- Keep changes focused and reviewable.

Before submitting:

- [ ] Code builds
- [ ] Tests pass
- [ ] Documentation updated
- [ ] API changes discussed

## Provider Integrations

Provider implementations should:

- Conform to shared abstractions.
- Avoid leaking provider-specific concepts into public APIs.
- Preserve consistent behavior across providers.

## Code of Conduct

By participating, you agree to follow the project's Code of Conduct (see `CODE_OF_CONDUCT.md`).

## Legal

By submitting a pull request, you represent that you have the right to license
your contribution to the community, and agree by submitting the patch
that your contributions are licensed under the Apache 2.0 license (see
`LICENSE`).
