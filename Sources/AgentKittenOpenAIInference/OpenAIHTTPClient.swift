// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Streams SSE events from OpenAI Chat Completions API requests.
protocol OpenAIHTTPStreaming: Sendable {
    func stream(request: OpenAIRequest) -> AsyncThrowingStream<OpenAISSEEvent, Error>
}

/// Sends requests to the OpenAI Chat Completions API (or any compatible endpoint) and streams SSE responses.
///
/// The `baseURL` parameter accepts any OpenAI-compatible API endpoint, enabling
/// local model serving via LM Studio at e.g. `http://localhost:1234/v1`.
struct OpenAIHTTPClient: OpenAIHTTPStreaming {
    private let apiKey: String
    private let baseURL: URL
    private let urlSession: URLSession

    static let providerName = "OpenAI"

    init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        urlSession = URLSession.shared
    }

    /// Streams SSE events from a single Chat Completions request.
    ///
    /// On Darwin platforms this uses incremental byte streaming from `URLSession`.
    /// On non-Darwin platforms it falls back to buffering the full response body
    /// because `FoundationNetworking` does not expose the same streaming API surface.
    func stream(request: OpenAIRequest) -> AsyncThrowingStream<OpenAISSEEvent, Error> {
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

    // MARK: - Private

    static func error(statusCode: Int, body: String) -> InferenceError {
        let fallbackMessage = "OpenAI API returned HTTP \(statusCode): \(body)"
        let message = parsedErrorMessage(body) ?? fallbackMessage
        guard isContextWindowExceeded(statusCode: statusCode, errorMessage: message) else {
            return .invalidResponse(fallbackMessage)
        }
        return .contextWindowExceeded(
            ContextWindowExceededInfo(provider: Self.providerName, message: message),
        )
    }

    /// Parses the OpenAI JSON error body to extract the structured error message.
    ///
    /// OpenAI error responses have the shape `{"error":{"message":"...","type":"...","code":"..."}}`.
    private static func parsedErrorMessage(_ body: String) -> String? {
        guard
            let data = body.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }
        return message
    }

    private static func isContextWindowExceeded(statusCode: Int, errorMessage: String) -> Bool {
        guard statusCode == 400 || statusCode == 413 else {
            return false
        }
        let normalized = errorMessage.lowercased()
        let code = normalized.contains("context_length_exceeded")
        let keywords = normalized.contains("context window")
            || (normalized.contains("token") && normalized.contains("exceed"))
            || (normalized.contains("tokens") && normalized.contains("maximum"))
        return code || keywords
    }

    private func streamSSEEvents(
        for request: URLRequest,
        continuation: AsyncThrowingStream<OpenAISSEEvent, Error>.Continuation,
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

        for try await event in OpenAISSEParser.events(from: bytes) {
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
        // the full SSE response body before parsing it into lines.
        for try await event in OpenAISSEParser.events(from: data) {
            try Task.checkCancellation()
            continuation.yield(event)
        }
        #endif
    }

    private func buildURLRequest(for request: OpenAIRequest) throws -> URLRequest {
        let endpoint = baseURL.appending(path: "chat/completions")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return urlRequest
    }
}
#endif
