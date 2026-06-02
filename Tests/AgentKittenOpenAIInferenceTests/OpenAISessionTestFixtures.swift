// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenCore
import AgentKittenInferenceSupport
@testable import AgentKittenOpenAIInference
import Foundation
import Synchronization

/// A mock OpenAI HTTP client that returns pre-set SSE event sequences in order
/// and records the requests it received.
final class MockOpenAIHTTPClient: OpenAIHTTPStreaming, @unchecked Sendable {
    private struct State {
        var queue: [[OpenAISSEEvent]]
        var requests: [OpenAIRequest] = []
    }

    private let state: Mutex<State>

    var callCount: Int {
        state.withLock { $0.requests.count }
    }

    var capturedRequests: [OpenAIRequest] {
        state.withLock { $0.requests }
    }

    init(responses: [[OpenAISSEEvent]]) {
        state = Mutex(State(queue: responses))
    }

    func stream(request: OpenAIRequest) async throws -> AsyncThrowingStream<OpenAISSEEvent, Error> {
        let events = state.withLock { state in
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

func makeOpenAITestSession(
    registry: ToolRegistry = ToolRegistry(),
    client: MockOpenAIHTTPClient,
    systemPrompt: String? = nil,
    defaultModel: String = "test-model",
) -> OpenAIInferenceSession {
    OpenAIInferenceSession(
        client: client,
        defaultModel: defaultModel,
        systemPrompt: systemPrompt,
        toolRuntime: testOpenAIToolRuntime(registry: registry),
    )
}

func testOpenAIToolRuntime(registry: ToolRegistry = ToolRegistry()) -> ToolRuntime {
    ToolRuntime(
        toolDefinition: ToolDefinition(tools: registry.all),
        toolBehavior: ToolBehavior(),
    )
}

struct OpenAIStructuredAnswer: Codable, Sendable, JSONSchemaProviding, Equatable {
    let answer: String

    static var jsonSchema: JSONSchema {
        .object(properties: ["answer": .string(description: "The answer.")], required: ["answer"])
    }
}
#endif
