// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Reads an API key from a process environment variable.
///
/// Suitable for CLI tools, CI pipelines, and the AgentKitten Playground.
///
/// ```swift
/// let credentials = EnvironmentAPIKeyProvider("ANTHROPIC_API_KEY")
/// let credentials = EnvironmentAPIKeyProvider("OPENAI_API_KEY")
/// ```
public struct EnvironmentAPIKeyProvider: APIKeyProviding {
    private let variableName: String

    /// Creates a provider that reads from the given environment variable.
    ///
    /// - Parameter variableName: The environment variable to read.
    public init(_ variableName: String) {
        self.variableName = variableName
    }

    public func apiKey() async throws -> String {
        guard let value = ProcessInfo.processInfo.environment[variableName], !value.isEmpty else {
            throw APIKeyError.missing("Environment variable '\(variableName)' is not set or is empty.")
        }
        return value
    }
}
