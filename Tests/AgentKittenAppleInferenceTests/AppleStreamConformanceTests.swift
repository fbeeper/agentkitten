// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
@testable import AgentKittenAppleInference
import AgentKittenCore
import AgentKittenInferenceTestSupport
import Testing

// Smoke-checks that the Apple provider's event-emission path produces streams
// satisfying the shared `InferenceEvent` contract.
//
// The on-device model is unavailable in CI, so this drives `ToolEventRelay` —
// the offline primitive every Apple turn emits through — with a representative
// well-formed turn and validates it with `InferenceStreamValidator`.

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func appleRelayTurnSatisfiesStreamContract() async throws {
    let relay = ToolEventRelay()
    let (stream, continuation) = InferenceStream.makeStream()
    let turn = await relay.beginTurn(continuation)

    await relay.emit(.delta("Looking that up"))
    await relay.emit(.toolCallRequested(id: "call-1", name: "lookup", argumentsJSON: "{}"))
    await relay.emit(.toolCallCompleted(
        id: "call-1",
        name: "lookup",
        outcome: .success(content: [.text("ok")]),
    ))
    await relay.emit(.result("Looking that up — done", .endTurn))
    await relay.endTurn(turn)
    continuation.finish()

    let events = try await InferenceStreamValidator.validate(stream)
    guard case .result = events.last else {
        Issue.record("Expected the stream to terminate with `.result`.")
        return
    }
}
#endif
