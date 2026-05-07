// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Immutable custom execution values visible to inference sessions.
///
/// Carries ``ExecutionConfigurationDomain/inference`` domain values into
/// ``InferenceRequestParameters`` so sessions can read them per-request.
/// Providers that bind model identity at the request level (e.g. Anthropic)
/// read their model key here on every turn; providers that bind at session
/// construction time (e.g. Apple) receive this context in
/// ``InferenceProviding/makeSession(systemPrompt:toolRuntime:toolSelection:inferenceContext:)``.
public struct InferenceContext: Sendable, Equatable, Hashable {
    /// An empty inference context.
    public static let empty = InferenceContext()

    private var storage: CustomContext

    /// Creates an empty inference context.
    public init() {
        self.storage = CustomContext()
    }

    init(customValues: [String: ExecutionConfigurationCustomValue]) {
        self.storage = CustomContext(customValues: customValues)
    }

    /// Reads or writes a typed inference value.
    public subscript<Key: ExecutionConfigurationKey>(_ key: Key.Type) -> Key.Value? {
        get {
            storage[key]
        }
        set {
            storage[key] = newValue
        }
    }

    var traceSnapshot: CustomContextSnapshot? {
        storage.traceSnapshot
    }
}
