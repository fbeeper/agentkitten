// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
@testable import AgentKittenInference
import Testing

// MARK: - ToolEventRelay

// `ToolEventRelay` does not depend on Apple Intelligence being available —
// it is a plain actor over `AsyncThrowingStream` continuations. These tests
// exercise it directly to verify ordering and cancellation semantics without
// requiring the on-device model.

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func relay_forwardsEventsInOrder() async throws {
    let relay = ToolEventRelay()
    let (stream, continuation) = InferenceStream.makeStream()
    let turn = await relay.beginTurn(continuation)

    await relay.emit(.delta("a"))
    await relay.emit(.delta("b"))
    await relay.emit(.delta("c"))
    await relay.endTurn(turn)
    continuation.finish()

    var received: [InferenceEvent<String>] = []
    for try await event in stream {
        received.append(event)
    }

    #expect(received.count == 3)
    guard case .delta(let chunk0) = received[0],
          case .delta(let chunk1) = received[1],
          case .delta(let chunk2) = received[2] else {
        Issue.record("Expected three textDelta events"); return
    }
    #expect(chunk0 == "a")
    #expect(chunk1 == "b")
    #expect(chunk2 == "c")
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func relay_dropsEventsAfterCleared() async throws {
    let relay = ToolEventRelay()
    let (stream, continuation) = InferenceStream.makeStream()
    let turn = await relay.beginTurn(continuation)

    await relay.emit(.delta("before"))
    await relay.endTurn(turn)
    await relay.emit(.delta("after")) // must be dropped
    continuation.finish()

    var received: [InferenceEvent<String>] = []
    for try await event in stream {
        received.append(event)
    }

    #expect(received.count == 1)
    guard case .delta(let text) = received[0] else {
        Issue.record("Expected a textDelta event"); return
    }
    #expect(text == "before")
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func relay_emitWithNilContinuationIsNoop() async {
    let relay = ToolEventRelay()
    // Emit without ever setting a continuation — must not crash.
    await relay.emit(.delta("dropped"))
    await relay.emit(.result("done", .endTurn))
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func relay_replacingContinuationRedirectsEvents() async throws {
    let relay = ToolEventRelay()
    let (stream1, cont1) = InferenceStream.makeStream()
    let (stream2, cont2) = InferenceStream.makeStream()

    let turn1 = await relay.beginTurn(cont1)
    await relay.emit(.delta("first"))
    await relay.endTurn(turn1)
    cont1.finish()

    let turn2 = await relay.beginTurn(cont2)
    await relay.emit(.delta("second"))
    await relay.endTurn(turn2)
    cont2.finish()

    var events1: [InferenceEvent<String>] = []
    for try await event in stream1 {
        events1.append(event)
    }

    var events2: [InferenceEvent<String>] = []
    for try await event in stream2 {
        events2.append(event)
    }

    #expect(events1.count == 1)
    #expect(events2.count == 1)
    guard case .delta(let text1) = events1[0],
          case .delta(let text2) = events2[0] else {
        Issue.record("Expected textDelta in each stream"); return
    }
    #expect(text1 == "first")
    #expect(text2 == "second")
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func relay_staleTurnEndDoesNotClearCurrentContinuation() async throws {
    let relay = ToolEventRelay()
    let (stream1, cont1) = InferenceStream.makeStream()
    let (stream2, cont2) = InferenceStream.makeStream()

    let turn1 = await relay.beginTurn(cont1)
    await relay.emit(.delta("first"))

    _ = await relay.beginTurn(cont2)
    await relay.endTurn(turn1)
    await relay.emit(.delta("second"))
    cont1.finish()
    cont2.finish()

    var events1: [InferenceEvent<String>] = []
    for try await event in stream1 {
        events1.append(event)
    }

    var events2: [InferenceEvent<String>] = []
    for try await event in stream2 {
        events2.append(event)
    }

    #expect(events1.count == 1)
    #expect(events2.count == 1)
    guard case .delta(let text1) = events1[0],
          case .delta(let text2) = events2[0] else {
        Issue.record("Expected textDelta in each stream"); return
    }
    #expect(text1 == "first")
    #expect(text2 == "second")
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func relay_toolEventOrderingMatchesEmitOrder() async throws {
    // Verifies the specific sequence AppleBridgedTool emits:
    // toolCallRequested → toolApprovalRequired → toolCallCompleted, interleaved with text deltas.
    let relay = ToolEventRelay()
    let (stream, continuation) = InferenceStream.makeStream()
    let turn = await relay.beginTurn(continuation)

    let callID = "abc-123"
    let pendingCall = PendingToolCall(id: callID, name: "echo", argumentsJSON: "{}")
    await relay.emit(.delta("preamble"))
    await relay.emit(.toolCallRequested(id: callID, name: "echo", argumentsJSON: "{}"))
    await relay.emitApprovalRequired(call: pendingCall)
    await relay.emit(.toolCallCompleted(id: callID, name: "echo", outcome: .success(content: [.text("{}")])))
    await relay.emit(.delta("reply"))
    await relay.endTurn(turn)
    continuation.finish()

    var received: [InferenceEvent<String>] = []
    for try await event in stream {
        received.append(event)
    }

    #expect(received.count == 5)
    guard case .delta(let pre) = received[0] else {
        Issue.record("Expected textDelta at 0"); return
    }
    guard case .toolCallRequested(let reqID, _, _) = received[1] else {
        Issue.record("Expected toolCallRequested at 1"); return
    }
    guard case .toolApprovalRequired(let approval) = received[2] else {
        Issue.record("Expected toolApprovalRequired at 2"); return
    }
    guard case .toolCallCompleted(let compID, _, _) = received[3] else {
        Issue.record("Expected toolCallCompleted at 3"); return
    }
    guard case .delta(let reply) = received[4] else {
        Issue.record("Expected textDelta at 4"); return
    }
    #expect(pre == "preamble")
    #expect(reqID == callID)
    #expect(approval == pendingCall)
    #expect(compID == callID)
    #expect(reply == "reply")
}
#endif
