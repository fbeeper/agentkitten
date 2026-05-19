// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

private struct PolicyEchoTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let message: String
    }

    struct Output: Codable, Sendable {
        let echo: String
    }

    static let name = "echo"
    static let defaultDescription = "Echoes the provided message."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["message": .string(description: "The message to echo.")],
            required: ["message"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(echo: arguments.message)
    }
}

private struct DenyAllPolicy: ToolExecutionPolicy {
    let reason: String

    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .deny(reason: reason)
    }
}

private struct DenyNamedPolicy: ToolExecutionPolicy {
    let deniedName: String
    let reason: String

    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        call.name == deniedName ? .deny(reason: reason) : .execute
    }
}

private enum ToolApprovalReasonKey: ExecutionConfigurationKey {
    static let id = "toolApprovalReason"
    static let domains: Set<ExecutionConfigurationDomain> = [.toolApproval]
    typealias Value = String
}

private enum HiddenPolicyReasonKey: ExecutionConfigurationKey {
    static let id = "hiddenPolicyReason"
    static let domains: Set<ExecutionConfigurationDomain> = [ExecutionConfigurationDomain(rawValue: "hidden")]
    typealias Value = String
}

private actor PolicyContextRecorder {
    private var approvalReason: String?
    private var hiddenReason: String?

    func record(approvalReason: String?, hiddenReason: String?) {
        self.approvalReason = approvalReason
        self.hiddenReason = hiddenReason
    }

    func snapshot() -> (approvalReason: String?, hiddenReason: String?) {
        (approvalReason, hiddenReason)
    }
}

private struct ContextReadingPolicy: ToolExecutionPolicy {
    let recorder: PolicyContextRecorder

    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        let approvalReason = context[ToolApprovalReasonKey.self]
        let hiddenReason = context[HiddenPolicyReasonKey.self]
        await recorder.record(
            approvalReason: approvalReason,
            hiddenReason: hiddenReason,
        )
        return .deny(reason: approvalReason ?? "missing approval reason")
    }
}

private actor SpyRecorder {
    private var count = 0

    func recordCall() {
        count += 1
    }

    func callCount() -> Int {
        count
    }
}

private struct SpyWriteFileTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let path: String
    }

    struct Output: Codable, Sendable {
        let success: Bool
    }

    static let name = "write_file"
    static let defaultDescription = "Writes a file."

    let recorder: SpyRecorder

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["path": .string(description: "The file path.")],
            required: ["path"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        await recorder.recordCall()
        return Output(success: true)
    }
}

private struct MultiToolProvider: InferenceProviding {
    typealias Session = MultiToolSession

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> MultiToolSession {
        MultiToolSession(toolRuntime: toolRuntime)
    }
}

private actor MultiToolSession: InferenceSession, StructuredInferenceSession {
    private let toolRuntime: ToolRuntime

    init(toolRuntime: ToolRuntime) {
        self.toolRuntime = toolRuntime
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
            toolStepBudget: parameters.toolStepBudget,
            context: parameters.toolExecutionContext,
        )
        let calls = [
            PendingToolCall(id: "call-1", name: "write_file", argumentsJSON: #"{"path":"/tmp/file.txt"}"#),
            PendingToolCall(id: "call-2", name: "echo", argumentsJSON: #"{"message":"hi"}"#),
        ]
        let (stream, continuation) = InferenceStream.makeStream()
        let task = Task {
            for call in calls {
                await Self.emitOutcome(
                    for: call,
                    toolTurnRuntime: toolTurnRuntime,
                    continuation: continuation,
                )
            }
            continuation.yield(.result("Done.", .endTurn))
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        throw .generationFailed(InferenceError.invalidResponse("structured generation not supported"))
    }
}

extension MultiToolSession {
    private static func emitOutcome(
        for call: PendingToolCall,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: InferenceStream.Continuation,
    ) async {
        continuation.yield(
            .toolCallRequested(
                id: call.id,
                name: call.name,
                argumentsJSON: call.argumentsJSON,
            ),
        )
        let outcome = await toolTurnRuntime.invoke(
            call,
            onApprovalRequired: { pendingCall in
                continuation.yield(.toolApprovalRequired(call: pendingCall))
            },
        )
        continuation.yield(
            .toolCallCompleted(
                id: call.id,
                name: call.name,
                outcome: outcome,
            ),
        )
    }
}

@Test func denyAllPolicyProducesDeniedToolFailureAndSkipsExecution() async throws {
    let recorder = SpyRecorder()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [
            .toolCall(
                name: "write_file",
                argumentsJSON: #"{"path":"/tmp/file.txt"}"#,
                thenRespond: "Done.",
            ),
        ])),
        behavior: .test(),
        toolDefinition: ToolDefinition(
            tools: [AnyAgentTool(SpyWriteFileTool(recorder: recorder))],
            executionPolicy: DenyAllPolicy(reason: "blocked"),
        ),
    )
    let session = agent.makeSession()

    var sawDeniedFailure = false
    for try await event in try await session.send("go").events {
        guard case .toolCallCompleted(let name, _, let outcome) = event.kind else {
            continue
        }
        if name == "write_file",
           case .failure(.denied(let reason)) = outcome {
            sawDeniedFailure = reason == "blocked"
        }
    }

    #expect(sawDeniedFailure)
    #expect(await recorder.callCount() == 0)
}

@Test func denyNamedPolicyAllowsOtherToolsInSameTurn() async throws {
    let recorder = SpyRecorder()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: MultiToolProvider()),
        behavior: .test(),
        toolDefinition: ToolDefinition(
            tools: [
                AnyAgentTool(SpyWriteFileTool(recorder: recorder)),
                AnyAgentTool(PolicyEchoTool()),
            ],
            executionPolicy: DenyNamedPolicy(deniedName: "write_file", reason: "blocked"),
        ),
    )
    let session = agent.makeSession()
    let turn = try await session.send("go")

    var writeFailure: ToolCallFailure?
    var echoSucceeded = false
    for try await event in turn.events {
        guard case .toolCallCompleted(let name, _, let outcome) = event.kind else {
            continue
        }
        switch (name, outcome) {
        case ("write_file", .failure(let failure)):
            writeFailure = failure
        case ("echo", .success):
            echoSucceeded = true
        default:
            break
        }
    }

    #expect(writeFailure == .denied(reason: "blocked"))
    #expect(echoSucceeded)
    #expect(await recorder.callCount() == 0)
}

@Test func toolApprovalContextSurfacesOnlyToolApprovalDomainProperties() async throws {
    let policyRecorder = PolicyContextRecorder()
    let toolRecorder = SpyRecorder()
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider(responses: [
            .toolCall(
                name: "write_file",
                argumentsJSON: #"{"path":"/tmp/file.txt"}"#,
                thenRespond: "Done.",
            ),
        ])),
        behavior: .test(),
        toolDefinition: ToolDefinition(
            tools: [AnyAgentTool(SpyWriteFileTool(recorder: toolRecorder))],
            executionPolicy: ContextReadingPolicy(recorder: policyRecorder),
        ),
    )
    let session = agent.makeSession()
    var turnOverrides = TurnOverrides()
    turnOverrides[ToolApprovalReasonKey.self] = "blocked by turn config"
    turnOverrides[HiddenPolicyReasonKey.self] = "should not surface"

    var denialReason: String?
    for try await event in try await session.send("go", turnOverrides: turnOverrides).events {
        guard case .toolCallCompleted(_, _, let outcome) = event.kind,
              case .failure(.denied(let reason)) = outcome else {
            continue
        }
        denialReason = reason
    }
    let observed = await policyRecorder.snapshot()

    #expect(denialReason == "blocked by turn config")
    #expect(observed.approvalReason == "blocked by turn config")
    #expect(observed.hiddenReason == nil)
    #expect(await toolRecorder.callCount() == 0)
}

@Test func deniedFailureResultJSONContainsReason() {
    let resultJSON = ToolCallFailure.denied(reason: "blocked by policy").resultJSON
    #expect(resultJSON.contains("blocked by policy"))
}

@Test func deniedFailureCodableRoundTrips() throws {
    let original = ToolCallFailure.denied(reason: "blocked")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ToolCallFailure.self, from: data)
    #expect(decoded == original)
}
