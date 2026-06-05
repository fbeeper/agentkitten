// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenInferenceSupport

/// The credential strategy for an ``OpenAIInferenceProvider``.
public enum OpenAICredentials: Sendable {
    /// Fetches a bearer token from the supplied `APIKeyProviding` on each request.
    case key(any APIKeyProviding)
    /// Sends no `Authorization` header.  For local servers like LM Studio that accept unauthenticated requests.
    case noCredential
}
#endif
