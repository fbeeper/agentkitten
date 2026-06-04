// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import AgentKittenInferenceSupport
import Synchronization

// MARK: - Mock HTTP clients

/// Records how many times `stream(request:)` was called and returns pre-set
/// SSE event sequences in order.
final class MockHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private struct State {
        var queue: [[SSEEvent]]
        var callCount = 0
        var requests: [AnthropicRequest] = []
    }

    private let state: Mutex<State>

    var callCount: Int {
        state.withLock { $0.callCount }
    }

    var capturedRequests: [AnthropicRequest] {
        state.withLock { $0.requests }
    }

    init(responses: [[SSEEvent]]) {
        state = Mutex(State(queue: responses))
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        let events = state.withLock { state in
            state.callCount += 1
            state.requests.append(request)
            return state.queue.isEmpty ? [] : state.queue.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

final class CapturingStructuredHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let capturedRequestState = Mutex<AnthropicRequest?>(nil)
    private let events: [SSEEvent]

    var capturedRequest: AnthropicRequest? {
        capturedRequestState.withLock { $0 }
    }

    init(events: [SSEEvent]) {
        self.events = events
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        capturedRequestState.withLock { $0 = request }
        let events = events
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

final class SequencedHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let clients: [any AnthropicHTTPStreaming]
    private let index = Mutex(0)

    init(clients: [any AnthropicHTTPStreaming]) {
        self.clients = clients
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        let clientIndex = index.withLock { value in
            defer { value += 1 }
            return value
        }
        let client = clients[clientIndex]
        return client.stream(request: request)
    }
}

// MARK: - Session factory helper

func makeSession(
    toolExecutionPolicy: some ToolExecutionPolicy = AutoApprovePolicy(),
    maxEmptyToolUseFollowUps: Int = 8,
    client: any AnthropicHTTPStreaming,
) -> AnthropicInferenceSession {
    AnthropicInferenceSession(
        client: client,
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(executionPolicy: toolExecutionPolicy),
        maxEmptyToolUseFollowUps: maxEmptyToolUseFollowUps,
    )
}

#endif
