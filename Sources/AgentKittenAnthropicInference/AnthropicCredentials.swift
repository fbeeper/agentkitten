// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenInferenceSupport

/// The credential strategy for an ``AnthropicInferenceProvider``.
public enum AnthropicCredentials: Sendable {
    /// Fetches an API key from the supplied `APIKeyProviding` on each request.
    case key(any APIKeyProviding)
    /// Sends no `x-api-key` header. For proxies or local servers that accept unauthenticated requests.
    case noCredential
}
#endif
