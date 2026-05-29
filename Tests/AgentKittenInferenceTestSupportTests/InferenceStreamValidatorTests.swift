// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import AgentKittenInferenceTestSupport
import Testing

@Suite("InferenceStreamValidator contract checks")
struct InferenceStreamValidatorTests {
    private func completion(_ id: ToolCallID) -> InferenceEvent<String> {
        .toolCallCompleted(id: id, name: "tool", outcome: .success(content: [.text("ok")]))
    }

    private func request(_ id: ToolCallID) -> InferenceEvent<String> {
        .toolCallRequested(id: id, name: "tool", argumentsJSON: "{}")
    }

    @Test("Well-formed text stream passes and returns its events")
    func wellFormedTextStream() async throws {
        let events = try await InferenceStreamValidator.validate(
            makeInferenceEventStream([
                .delta("Hel"),
                .delta("lo"),
                .result("Hello", .endTurn),
            ]),
        )
        #expect(events.count == 3)
    }

    @Test("Explicit nil provider error finishes cleanly")
    func nilProviderErrorFinishesCleanly() async throws {
        let events = try await InferenceStreamValidator.validate(
            makeInferenceEventStream([
                .delta("ok"),
                .result("ok", .endTurn),
            ], failingWith: nil),
        )
        #expect(events.count == 2)
    }

    @Test("Parallel tool calls closing in any order pass")
    func parallelToolCalls() async throws {
        try await InferenceStreamValidator.validate(
            makeInferenceEventStream([
                request("a"),
                request("b"),
                completion("a"),
                completion("b"),
                .result("done", .endTurn),
            ]),
        )
    }

    @Test("Approval after its matching request passes")
    func approvalAfterRequest() async throws {
        let call = PendingToolCall(id: "a", name: "tool", argumentsJSON: "{}")
        try await InferenceStreamValidator.validate(
            makeInferenceEventStream([
                request("a"),
                .toolApprovalRequired(call: call),
                completion("a"),
                .result("done", .endTurn),
            ]),
        )
    }

    @Test("Stream without a result is rejected")
    func missingResult() async throws {
        await #expect(throws: InferenceStreamContractViolation.missingResult) {
            try await InferenceStreamValidator.validate(
                makeInferenceEventStream([.delta("hi")] as [InferenceEvent<String>]),
            )
        }
    }

    @Test("Event after result is rejected")
    func eventAfterResult() async throws {
        await #expect(throws: InferenceStreamContractViolation.eventAfterResult) {
            try await InferenceStreamValidator.validate(
                makeInferenceEventStream([
                    .result("done", .endTurn),
                    .delta("trailing"),
                ]),
            )
        }
    }

    @Test("Completion without a matching request is rejected")
    func completionWithoutRequest() async throws {
        await #expect(throws: InferenceStreamContractViolation.completionWithoutRequest("a")) {
            try await InferenceStreamValidator.validate(
                makeInferenceEventStream([
                    completion("a"),
                    .result("done", .endTurn),
                ]),
            )
        }
    }

    @Test("Result with an open tool call is rejected")
    func resultWithOpenToolCall() async throws {
        await #expect(throws: InferenceStreamContractViolation.openToolCallsAtResult(Set(["a"]))) {
            try await InferenceStreamValidator.validate(
                makeInferenceEventStream([
                    request("a"),
                    .result("done", .endTurn),
                ]),
            )
        }
    }

    @Test("Approval without a preceding request is rejected")
    func approvalWithoutRequest() async throws {
        let call = PendingToolCall(id: "a", name: "tool", argumentsJSON: "{}")
        await #expect(throws: InferenceStreamContractViolation.approvalWithoutRequest("a")) {
            try await InferenceStreamValidator.validate(
                makeInferenceEventStream([
                    .toolApprovalRequired(call: call),
                    .result("done", .endTurn),
                ]),
            )
        }
    }

    @Test("Reusing an open tool-call id is rejected")
    func duplicateOpenToolCall() async throws {
        await #expect(throws: InferenceStreamContractViolation.duplicateOpenToolCall("a")) {
            try await InferenceStreamValidator.validate(
                makeInferenceEventStream([
                    request("a"),
                    request("a"),
                    .result("done", .endTurn),
                ]),
            )
        }
    }

    @Test("A thrown provider error is a valid terminal, re-thrown unchanged")
    func providerErrorRethrown() async throws {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await InferenceStreamValidator.validate(
                makeInferenceEventStream([.delta("partial")] as [InferenceEvent<String>], failingWith: Boom()),
            )
        }
    }
}

func makeInferenceEventStream<Output: Sendable>(
    _ events: [InferenceEvent<Output>],
    failingWith error: Error? = nil,
) -> AsyncThrowingStream<InferenceEvent<Output>, Error> {
    AsyncThrowingStream { continuation in
        for event in events {
            continuation.yield(event)
        }
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
