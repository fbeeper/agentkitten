// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Details for a provider context-window overflow.
public struct ContextWindowExceededInfo: Sendable, Equatable, Hashable, Codable {
    /// Provider or backend that reported the overflow, if known.
    public let provider: String?
    /// Human-readable provider message.
    public let message: String
    /// Estimated context tokens involved in the failed request, if known.
    public let contextTokens: Int?
    /// Provider/model context window, if known.
    public let contextSize: Int?

    /// Creates context-window overflow details.
    public init(
        provider: String? = nil,
        message: String,
        contextTokens: Int? = nil,
        contextSize: Int? = nil,
    ) {
        self.provider = provider
        self.message = message
        self.contextTokens = contextTokens
        self.contextSize = contextSize
    }
}

/// Details for a provider-side authentication failure.
public struct AuthenticationFailureInfo: Sendable, Equatable, Hashable, Codable {
    /// Provider or backend that reported the failure.
    public let provider: String
    /// Human-readable failure message. Must not contain credential secret values.
    public let message: String
    /// HTTP status code when the provider rejected authentication.
    public let statusCode: Int

    /// Creates authentication failure details.
    public init(
        provider: String,
        message: String,
        statusCode: Int,
    ) {
        self.provider = provider
        self.message = message
        self.statusCode = statusCode
    }
}

/// Errors that can arise during inference.
public enum InferenceError: Error, Sendable, Equatable, Hashable, Codable {
    /// Another inference-session operation is already running.
    case concurrentOperationInProgress(active: InferenceSessionOperationKind)

    /// The provider is not available on this device or configuration.
    ///
    /// Examples: model not downloaded, Apple Intelligence disabled, no API key.
    case providerUnavailable(String)

    /// The stream ended before yielding `.finished`, without throwing an error.
    case streamInterrupted

    /// The provider returned a response that could not be interpreted.
    case invalidResponse(String)

    /// The requested configuration is unsupported by the provider.
    case unsupportedConfiguration(String)

    /// The provider rejected the turn because the session context exceeded the model window.
    case contextWindowExceeded(ContextWindowExceededInfo)

    /// The provider rejected authentication for the request.
    case authenticationFailed(AuthenticationFailureInfo)
}

/// Inference-session operations that require exclusive access.
public enum InferenceSessionOperationKind: String, Sendable, Equatable, Hashable, Codable {
    /// Unstructured turn execution.
    case run

    /// Structured turn execution.
    case generate

    /// Session context clearing.
    case clearContext

    /// Session rebuild.
    case rebuildSession

    /// Manual context compaction.
    case compactContext

    /// Context-usage inspection.
    case contextUsage
}
