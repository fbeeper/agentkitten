// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

private struct RequiresApprovalPolicy: ToolExecutionPolicy {
    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .requiresApproval
    }
}

private enum TraceApprovalReasonKey: ExecutionConfigurationKey {
    static let id = "toolApprovalReason"
    static let domains: Set<ExecutionConfigurationDomain> = [.toolApproval]
    typealias Value = String
}

@Suite("Tool Approval Runtime")
struct ToolApprovalRuntimeTests {
    @Test func directTurn_approvalResumesSameTurnAndExecutesTool() async throws {
        let counter = ToolCallCounter()
        let session = makeApprovalSession(
            responses: [
                .toolCall(
                    name: CountingEchoTool.name,
                    argumentsJSON: #"{"message":"approved"}"#,
                    thenRespond: "Done.",
                ),
            ],
            tools: [AnyAgentTool(CountingEchoTool(counter: counter))],
        )
        let turn = await session.send("go")
        var iterator = turn.events.makeAsyncIterator()
        let approval = try await nextApprovalCall(from: &iterator)

        #expect(await counter.value() == 0)

        try await session.approve(callID: approval.id)

        var sawToolCompletion = false
        var completions: [String] = []
        while let event = try await iterator.next() {
            switch event.kind {
            case .toolCallCompleted(let name, let id, let outcome):
                if name == CountingEchoTool.name,
                   id == approval.id,
                   case .success = outcome {
                    sawToolCompletion = true
                }
            case .result(let assistant):
                completions.append(assistant.text)
            default:
                break
            }
        }

        #expect(await counter.value() == 1)
        #expect(sawToolCompletion)
        #expect(completions == ["Done."])
    }

    @Test func directTurn_denialResumesSameTurnWithoutExecutingTool() async throws {
        let counter = ToolCallCounter()
        let session = makeApprovalSession(
            responses: [
                .toolCall(
                    name: CountingEchoTool.name,
                    argumentsJSON: #"{"message":"denied"}"#,
                    thenRespond: "Done.",
                ),
            ],
            tools: [AnyAgentTool(CountingEchoTool(counter: counter))],
        )
        let turn = await session.send("go")
        var iterator = turn.events.makeAsyncIterator()
        let approval = try await nextApprovalCall(from: &iterator)

        try await session.deny(callID: approval.id, reason: "blocked")

        var deniedFailure: ToolCallFailure?
        var completions: [String] = []
        while let event = try await iterator.next() {
            switch event.kind {
            case .toolCallCompleted(let name, let id, let outcome):
                if name == CountingEchoTool.name,
                   id == approval.id,
                   case .failure(let failure) = outcome {
                    deniedFailure = failure
                }
            case .result(let assistant):
                completions.append(assistant.text)
            default:
                break
            }
        }

        #expect(await counter.value() == 0)
        #expect(deniedFailure == .denied(reason: "blocked"))
        #expect(completions == ["Done."])
    }

    @Test func trace_recordsToolApprovalExecutionContext() async throws {
        let counter = ToolCallCounter()
        let session = makeApprovalSession(
            responses: [
                .toolCall(
                    name: CountingEchoTool.name,
                    argumentsJSON: #"{"message":"denied"}"#,
                    thenRespond: "Done.",
                ),
            ],
            tools: [AnyAgentTool(CountingEchoTool(counter: counter))],
        )
        var turnOverrides = TurnOverrides()
        turnOverrides[TraceApprovalReasonKey.self] = "requires human review"

        let turn = await session.send("go", turnOverrides: turnOverrides)
        var iterator = turn.events.makeAsyncIterator()
        let approval = try await nextApprovalCall(from: &iterator)

        let traceEntry = try #require(
            await rawTraceEntries(for: turn.id, on: session).first {
                if case .toolApprovalRequired(let info) = $0.kind {
                    return info.call.id == approval.id
                }
                return false
            },
        )
        guard case .toolApprovalRequired(let info) = traceEntry.kind else {
            Issue.record("Expected tool approval trace entry")
            return
        }
        #expect(info.call == approval)
        #expect(info.context == CustomContextSnapshot(entries: [
            CustomContextSnapshot.Entry(key: TraceApprovalReasonKey.id, valueSummary: "requires human review"),
        ]))

        try await session.deny(callID: approval.id, reason: "blocked")
        while try await iterator.next() != nil {}

        #expect(await counter.value() == 0)
    }

    @Test func approvalResolution_unknownCallIDThrows() async throws {
        let gate = ToolApprovalGate()

        do {
            try await gate.approve(callID: "missing-call")
            Issue.record("Expected unknown approval resolution to throw")
        } catch let error as ToolApprovalResolutionError {
            #expect(error == .noPendingApproval(callID: "missing-call"))
        }
    }

    @Test func toolApprovalGate_duplicatePendingApprovalThrows() async throws {
        let gate = ToolApprovalGate()

        try await gate.register(callID: "call-1")
        let waitingRequest = Task {
            try await gate.waitForResolution(callID: "call-1")
        }

        await Task.yield()

        do {
            try await gate.register(callID: "call-1")
            Issue.record("Expected duplicate pending approval to throw")
        } catch let error as ToolApprovalResolutionError {
            #expect(error == .duplicatePendingApproval(callID: "call-1"))
        }

        try await gate.approve(callID: "call-1")
        let resolution = try await waitingRequest.value
        #expect(resolution == .approved)
    }

    @Test func toolApprovalGate_approveBeforeWaitForResolutionReturnsApproved() async throws {
        let gate = ToolApprovalGate()

        try await gate.register(callID: "call-1")
        try await gate.approve(callID: "call-1")

        let resolution = try await gate.waitForResolution(callID: "call-1")
        #expect(resolution == .approved)
    }

    @Test func toolApprovalGate_denyBeforeWaitForResolutionReturnsDeniedReason() async throws {
        let gate = ToolApprovalGate()

        try await gate.register(callID: "call-1")
        try await gate.deny(callID: "call-1", reason: "blocked")

        let resolution = try await gate.waitForResolution(callID: "call-1")
        #expect(resolution == .denied(reason: "blocked"))
    }

    @Test func toolApprovalGate_duplicateWaitThrows() async throws {
        let gate = ToolApprovalGate()

        try await gate.register(callID: "call-1")
        let firstWait = Task {
            try await gate.waitForResolution(callID: "call-1")
        }

        await Task.yield()

        do {
            _ = try await gate.waitForResolution(callID: "call-1")
            Issue.record("Expected duplicate pending wait to throw")
        } catch let error as ToolApprovalResolutionError {
            #expect(error == .duplicatePendingWait(callID: "call-1"))
        }

        await gate.cancel(callID: "call-1")
        _ = try await firstWait.value
    }

    @Test func queuedTurn_staysBlockedUntilPendingApprovalResolves() async throws {
        let counter = ToolCallCounter()
        let session = makeApprovalSession(
            responses: [
                .toolCall(
                    name: CountingEchoTool.name,
                    argumentsJSON: #"{"message":"first"}"#,
                    thenRespond: "First done.",
                ),
                .success("Second done."),
            ],
            tools: [AnyAgentTool(CountingEchoTool(counter: counter))],
        )
        let firstTurn = await session.send("first")
        var firstIterator = firstTurn.events.makeAsyncIterator()
        let approval = try await nextApprovalCall(from: &firstIterator)

        let secondTurn = await session.send("second")
        let trace = session.trace
        let traceBeforeApproval = await trace.snapshot()
        #expect(!traceBeforeApproval.contains { $0.invocationID == secondTurn.id })

        try await session.approve(callID: approval.id)

        var firstCompletions: [String] = []
        while let event = try await firstIterator.next() {
            if case .result(let assistant) = event.kind {
                firstCompletions.append(assistant.text)
            }
        }
        let secondCompletions = assistantCompletions(in: try await collectEvents(from: secondTurn))

        #expect(await counter.value() == 1)
        #expect(firstCompletions == ["First done."])
        #expect(secondCompletions == ["Second done."])
    }
}

private func makeApprovalSession(
    responses: [MockResponse],
    tools: [AnyAgentTool],
) -> AgentQueuedSession {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(
            responses: responses,
        )),
        behavior: .test(),
        toolDefinition: ToolDefinition(
            tools: tools,
            executionPolicy: RequiresApprovalPolicy(),
        ),
    )
    return agent.makeQueuedSession()
}
