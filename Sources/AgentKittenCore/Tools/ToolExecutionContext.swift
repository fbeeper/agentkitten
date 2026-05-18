// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Immutable custom turn values visible to ``ToolExecutionPolicy``.
public struct ToolExecutionContext: Sendable {
    /// An empty tool execution context.
    public static let empty = ToolExecutionContext()

    private let storage: CustomContext

    /// Creates an empty tool execution context.
    public init() {
        storage = CustomContext()
    }

    init(customValues: [String: ExecutionConfigurationCustomValue]) {
        storage = CustomContext(customValues: customValues)
    }

    /// Reads a typed custom turn value visible to tool policy.
    public subscript<Key: ExecutionConfigurationKey>(_ key: Key.Type) -> Key.Value? {
        storage[key]
    }

    var traceSnapshot: CustomContextSnapshot? {
        // `ToolExecutionContext` is already the tool-policy projection, so
        // snapshot everything present here instead of re-filtering by domain.
        storage.traceSnapshot
    }
}
