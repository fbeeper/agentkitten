// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore
@testable import AgentKittenInference

private actor BlockingHTTPState {
    private var continuations: [AsyncThrowingStream<SSEEvent, Error>.Continuation] = []
    private var startedCount = 0
    private var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func register(_ continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation) {
        continuations.append(continuation)
        startedCount += 1
        var remaining: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if startedCount >= waiter.target {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }

    func waitUntilStarted(turnCount: Int = 1) async {
        guard startedCount < turnCount else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((target: turnCount, continuation: continuation))
        }
    }

    func finish() {
        for continuation in continuations {
            continuation.yield(.textDelta("done"))
            continuation.yield(.stopReason("end_turn"))
            continuation.finish()
        }
        continuations.removeAll()
    }
}

private final class BlockingHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    let state = BlockingHTTPState()

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await state.register(continuation)
            }
        }
    }
}

private func makeBlockingSession(
    client: BlockingHTTPClient
) -> AnthropicInferenceSession {
    AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(executionPolicy: AutoApprovePolicy()),
        clientFactory: { _ in client }
    )
}

@Test func session_rejectsConcurrentRunsInsteadOfCancellingFirstRequest() async throws {
    let client = BlockingHTTPClient()
    let session = makeBlockingSession(client: client)

    let firstStream = try await session.run(UserMessage(text: "Hi"), parameters: InferenceRequestParameters())
    let firstTask = Task {
        for try await _ in firstStream {}
    }
    await client.state.waitUntilStarted()

    await #expect(throws: InferenceError.concurrentOperationInProgress(active: .run)) {
        _ = try await session.run(UserMessage(text: "Again"), parameters: InferenceRequestParameters())
    }

    await client.state.finish()
    _ = try await firstTask.value
}

@Test func session_allowsImmediateFollowUpRunAfterFirstStreamTerminates() async throws {
    let client = BlockingHTTPClient()
    let session = makeBlockingSession(client: client)

    let firstStream = try await session.run(UserMessage(text: "Hi"), parameters: InferenceRequestParameters())
    let firstTask = Task {
        for try await _ in firstStream {}
    }
    await client.state.waitUntilStarted()
    await client.state.finish()
    _ = try await firstTask.value

    let secondStream = try await session.run(UserMessage(text: "Again"), parameters: InferenceRequestParameters())
    let secondTask = Task {
        for try await _ in secondStream {}
    }
    await client.state.waitUntilStarted(turnCount: 2)
    await client.state.finish()
    _ = try await secondTask.value
}

@Test func session_rejectsContextUsageWhileRunIsInFlight() async throws {
    let client = BlockingHTTPClient()
    let session = makeBlockingSession(client: client)

    let stream = try await session.run(UserMessage(text: "Hi"), parameters: InferenceRequestParameters())
    let task = Task {
        for try await _ in stream {}
    }
    await client.state.waitUntilStarted()

    await #expect(throws: InferenceError.concurrentOperationInProgress(active: .run)) {
        _ = try await session.contextUsage()
    }

    await client.state.finish()
    _ = try await task.value
}
