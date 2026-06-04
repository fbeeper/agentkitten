// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Streams SSE events and counts tokens for Anthropic Messages API requests.
protocol AnthropicHTTPStreaming: Sendable {
    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error>
    func countTokens(request: AnthropicCountTokensRequest) async throws -> Int
    func maxInputTokens(for model: String) async throws -> Int?
}

extension AnthropicHTTPStreaming {
    func maxInputTokens(for model: String) async throws -> Int? {
        nil
    }
}

/// Sends requests to the Anthropic Messages API and streams SSE responses.
struct AnthropicHTTPClient: AnthropicHTTPStreaming {
    private let credentials: AnthropicCredentials
    private let baseURL: URL
    private let probesLMStudioMetadata: Bool
    private let urlSession: URLSession

    private static let anthropicVersion = "2023-06-01"
    static let providerName = "Anthropic"

    init(
        credentials: AnthropicCredentials,
        baseURL: URL = AnthropicInferenceProvider.defaultBaseURL,
        probesLMStudioMetadata: Bool = false,
    ) {
        self.credentials = credentials
        self.baseURL = baseURL
        self.probesLMStudioMetadata = probesLMStudioMetadata
        urlSession = URLSession.shared
    }

    /// Applies the `x-api-key` header for the configured credential strategy.
    ///
    /// ``AnthropicCredentials/noCredential`` sets no header, leaving the request
    /// unauthenticated for proxies or local servers that accept it.
    private func authorize(_ urlRequest: inout URLRequest) async throws {
        if case .key(let provider) = credentials {
            urlRequest.setValue(try await provider.apiKey(), forHTTPHeaderField: "x-api-key")
        }
    }

    /// Streams SSE events from a single Anthropic Messages API request.
    ///
    /// - Parameter request: The fully constructed request body.
    /// - Returns: An async stream of ``SSEEvent`` values.
    ///
    /// On Darwin platforms this uses incremental byte streaming from `URLSession`.
    /// On non-Darwin platforms it falls back to buffering the full response body
    /// before parsing SSE lines because `FoundationNetworking` does not expose the
    /// same streaming API surface.
    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try await buildURLRequest(for: request)
                    try await streamSSEEvents(for: urlRequest, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func countTokens(request: AnthropicCountTokensRequest) async throws -> Int {
        var urlRequest = URLRequest(url: baseURL.appending(path: "messages/count_tokens"))
        urlRequest.httpMethod = "POST"
        try await authorize(&urlRequest)
        urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await urlSession.data(for: urlRequest)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(bytes: data, encoding: .utf8) ?? ""
            throw Self.error(statusCode: httpResponse.statusCode, body: body)
        }
        return try JSONDecoder().decode(AnthropicTokenCountResponse.self, from: data).inputTokens
    }

    func maxInputTokens(for model: String) async throws -> Int? {
        // Opt-in: probe LM Studio's native REST API first. It reports the *served* context window
        // (the loaded instance's configured length), which is more appropriate than the theoretical
        // maximum — and LM Studio's Anthropic-compatible surface omits the window on `/models/{id}`
        // (or doesn't serve that route at all). Only when this yields nothing do we fall back to the
        // standard endpoint. Never run against the Anthropic host.
        if probesLMStudioMetadata, baseURL != AnthropicInferenceProvider.defaultBaseURL,
           let resolved = await LMStudioModelMetadata.contextWindow(baseURL: baseURL, model: model) {
            return resolved
        }
        let endpoint = baseURL.appending(path: "models").appending(path: model)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "GET"
        try await authorize(&urlRequest)
        urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await urlSession.data(for: urlRequest)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(bytes: data, encoding: .utf8) ?? ""
            throw Self.error(statusCode: httpResponse.statusCode, body: body)
        }
        return try JSONDecoder().decode(AnthropicModelInfoResponse.self, from: data).maxInputTokens
    }

    // MARK: - Private

    static func error(statusCode: Int, body: String) -> InferenceError {
        let error = AnthropicHTTPError(statusCode: statusCode, body: body)
        if error.isAuthenticationFailure {
            return .authenticationFailed(
                AuthenticationFailureInfo(
                    provider: Self.providerName,
                    message: error.message,
                    statusCode: statusCode,
                ),
            )
        }
        if error.isContextWindowExceeded {
            return .contextWindowExceeded(
                ContextWindowExceededInfo(provider: Self.providerName, message: error.message),
            )
        }
        return .invalidResponse(error.message)
    }

    private func streamSSEEvents(
        for request: URLRequest,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
    ) async throws {
        #if canImport(Darwin)
        let (bytes, response) = try await urlSession.bytes(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = try await Self.errorBody(from: bytes)
            throw Self.error(statusCode: httpResponse.statusCode, body: body)
        }

        for try await event in AnthropicSSEParser.events(from: bytes) {
            try Task.checkCancellation()
            continuation.yield(event)
        }
        #else
        let (data, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(bytes: data, encoding: .utf8) ?? ""
            throw Self.error(statusCode: httpResponse.statusCode, body: body)
        }

        // FoundationNetworking on non-Darwin platforms does not expose the same
        // incremental byte-streaming API as Darwin URLSession, so this fallback buffers
        // the full SSE response body before parsing it into lines. This preserves
        // compatibility at the cost of true incremental streaming on Linux.
        for try await event in AnthropicSSEParser.events(from: data) {
            try Task.checkCancellation()
            continuation.yield(event)
        }
        #endif
    }

    private func buildURLRequest(for request: AnthropicRequest) async throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: "messages"))
        urlRequest.httpMethod = "POST"
        try await authorize(&urlRequest)
        urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        return urlRequest
    }

    #if canImport(Darwin)
    private static func errorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return String(bytes: data, encoding: .utf8) ?? ""
    }
    #endif
}

private struct AnthropicErrorResponse: Decodable {
    let error: AnthropicErrorPayload
}

private struct AnthropicErrorPayload: Decodable {
    let type: String?
    let message: String?
}

private struct AnthropicHTTPError {
    let statusCode: Int
    let body: String
    let payload: AnthropicErrorPayload?

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
        payload = Self.payload(from: body)
    }

    var isAuthenticationFailure: Bool {
        statusCode == 401 || statusCode == 403
    }

    var isContextWindowExceeded: Bool {
        payload?.type == "invalid_request_error"
            && payload?.message?.lowercased().hasPrefix("prompt is too long") == true
    }

    var message: String {
        if isAuthenticationFailure {
            if let type = payload?.type {
                return "Anthropic API returned HTTP \(statusCode): authentication failed (error type: \(type))"
            }
            return "Anthropic API returned HTTP \(statusCode): authentication failed"
        }

        return "Anthropic API returned HTTP \(statusCode): \(payload?.message ?? String(body.prefix(512)))"
    }

    /// Parses the Anthropic JSON error body to extract structured error details.
    ///
    /// Anthropic error responses have the shape `{"type":"error","error":{"type":"...","message":"..."}}`.
    private static func payload(from body: String) -> AnthropicErrorPayload? {
        guard
            let data = body.data(using: .utf8),
            let response = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data)
        else {
            return nil
        }
        return response.error
    }
}
#endif
