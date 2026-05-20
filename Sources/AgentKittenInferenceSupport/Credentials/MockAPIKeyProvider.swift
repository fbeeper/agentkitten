// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A credential provider that always returns a fixed string.
///
/// For tests and previews only. Do not use with real API keys in production code.
///
/// ```swift
/// let credentials = MockAPIKeyProvider("sk-ant-test-key")
/// ```
public struct MockAPIKeyProvider: APIKeyProviding {
    private let key: String

    /// Creates a provider that always returns `key`.
    public init(_ key: String) {
        self.key = key
    }

    public func apiKey() async throws -> String {
        key
    }
}
