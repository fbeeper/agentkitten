// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Shared mutable store for the scratchpad plain-text file.
actor ScratchpadStore {
    private(set) var content: String

    init() {
        content = initialContent
    }

    /// Overwrites the scratchpad with `newContent`.
    func write(_ newContent: String) {
        content = newContent
    }
}

private let initialContent = """
struct Greeter {
    let name: String

    func greet() -> String {
        "Hello, \\(name)!"
    }
}
"""
