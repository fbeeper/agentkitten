// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
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
    private let apiKey: String
    private let urlSession: URLSession

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let countTokensEndpoint = URL(string: "https://api.anthropic.com/v1/messages/count_tokens")!
    private static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models")!
    private static let anthropicVersion = "2023-06-01"
    static let providerName = "Anthropic"

    init(apiKey: String) {
        self.apiKey = apiKey
        urlSession = URLSession.shared
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
                    let urlRequest = try buildURLRequest(for: request)
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
        var urlRequest = URLRequest(url: Self.countTokensEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await urlSession.data(for: urlRequest)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(bytes: data, encoding: .utf8).map { String($0.prefix(512)) } ?? ""
            throw Self.error(statusCode: httpResponse.statusCode, body: body)
        }
        return try JSONDecoder().decode(AnthropicTokenCountResponse.self, from: data).inputTokens
    }

    func maxInputTokens(for model: String) async throws -> Int? {
        let endpoint = Self.modelsEndpoint.appending(path: model)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await urlSession.data(for: urlRequest)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(bytes: data, encoding: .utf8).map { String($0.prefix(512)) } ?? ""
            throw Self.error(statusCode: httpResponse.statusCode, body: body)
        }
        return try JSONDecoder().decode(AnthropicModelInfoResponse.self, from: data).maxInputTokens
    }

    // MARK: - Private

    static func error(statusCode: Int, body: String) -> InferenceError {
        let fallbackMessage = "Anthropic API returned HTTP \(statusCode): \(body)"
        let message = parsedErrorMessage(body) ?? fallbackMessage
        if isAuthenticationFailure(statusCode: statusCode) {
            return .authenticationFailed(
                AuthenticationFailureInfo(
                    provider: Self.providerName,
                    message: message,
                    statusCode: statusCode,
                ),
            )
        }
        guard isContextWindowExceeded(statusCode: statusCode, errorMessage: message) else {
            return .invalidResponse(fallbackMessage)
        }
        return .contextWindowExceeded(
            ContextWindowExceededInfo(provider: Self.providerName, message: message),
        )
    }

    /// Parses the Anthropic JSON error body to extract the structured error message.
    ///
    /// Anthropic error responses have the shape `{"type":"error","error":{"type":"...","message":"..."}}`.
    private static func parsedErrorMessage(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    private static func isAuthenticationFailure(statusCode: Int) -> Bool {
        statusCode == 401 || statusCode == 403
    }

    private static func isContextWindowExceeded(statusCode: Int, errorMessage: String) -> Bool {
        guard statusCode == 400 || statusCode == 413 else {
            return false
        }
        let normalized = errorMessage.lowercased()
        return normalized.contains("prompt is too long")
            || normalized.contains("context window")
            || (normalized.contains("token") && normalized.contains("exceed"))
            || (normalized.contains("tokens") && normalized.contains("maximum"))
    }

    private func streamSSEEvents(
        for request: URLRequest,
        continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation,
    ) async throws {
        #if canImport(Darwin)
        let (bytes, response) = try await urlSession.bytes(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 512 { break }
            }
            throw Self.error(statusCode: httpResponse.statusCode, body: body)
        }

        for try await event in AnthropicSSEParser.events(from: bytes) {
            try Task.checkCancellation()
            continuation.yield(event)
        }
        #else
        let (data, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(bytes: data, encoding: .utf8).map { String($0.prefix(512)) } ?? ""
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

    private func buildURLRequest(for request: AnthropicRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        return urlRequest
    }
}
#endif
