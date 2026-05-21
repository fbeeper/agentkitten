// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
import AgentKittenCore
import AgentKittenInferenceSupport
import Synchronization

// MARK: - Model info HTTP client doubles

final class ModelInfoHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let maxInputTokensValue: Int?

    init(maxInputTokensValue: Int?) {
        self.maxInputTokensValue = maxInputTokensValue
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func countTokens(request: AnthropicCountTokensRequest) async throws -> Int {
        0
    }

    func maxInputTokens(for model: String) async throws -> Int? {
        maxInputTokensValue
    }
}

struct FailingModelInfoHTTPClient: AnthropicHTTPStreaming {
    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func countTokens(request: AnthropicCountTokensRequest) async throws -> Int {
        0
    }

    func maxInputTokens(for model: String) async throws -> Int? {
        throw InferenceError.invalidResponse("lookup failed")
    }
}

final class CountingModelInfoHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let callCountState = Mutex(0)

    var callCount: Int {
        callCountState.withLock { $0 }
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func countTokens(request: AnthropicCountTokensRequest) async throws -> Int {
        0
    }

    func maxInputTokens(for model: String) async throws -> Int? {
        callCountState.withLock { $0 += 1 }
        return 123_456
    }
}

#endif
