// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Supplies an API key on demand.
///
/// Conform to this protocol to implement custom credential sources — environment
/// variables, Keychain, secrets managers, or test stubs.
///
/// `apiKey()` is async and throwing so implementations can perform
/// asynchronous I/O (e.g., a network vault) or signal a missing or expired key.
public protocol APIKeyProviding: Sendable {
    /// Returns the current API key.
    ///
    /// - Throws: ``APIKeyError`` when the key is missing or cannot be read.
    func apiKey() async throws -> String
}

// MARK: - APIKeyError

/// Errors thrown by ``APIKeyProviding`` implementations.
public enum APIKeyError: Error, Sendable {
    /// The requested key is absent (environment variable unset, Keychain item missing).
    case missing(String)
    /// The credential store returned data that could not be decoded as a UTF-8 string.
    case invalidData(String)
    /// An underlying OS error occurred while reading the credential store.
    case underlyingError(String, any Error)
}
