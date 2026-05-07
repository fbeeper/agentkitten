// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import AgentKittenCore
import Testing
@testable import AgentKittenInference
@Test func packageManifest_declaresExpectedApplePlatforms() throws {
    let testsDirectory = URL(filePath: #filePath).deletingLastPathComponent()
    let packageFile = testsDirectory
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Package.swift")
    let manifest = try String(contentsOf: packageFile, encoding: .utf8)

    for expectedLine in [
        ".macOS(.v15),",
        ".iOS(.v17),",
        ".tvOS(.v17),",
        ".watchOS(.v10),",
        ".visionOS(.v1),",
        ".macCatalyst(.v17),",
    ] {
        #expect(manifest.contains(expectedLine))
    }
}
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private actor AppleToolCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private struct AppleStructuredAnswer: Codable, Sendable, JSONSchemaProviding, Equatable {
    let answer: String

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "answer": .string(description: "The final answer."),
            ],
            required: ["answer"]
        )
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private struct AppleRequiresApprovalPolicy: ToolExecutionPolicy {
    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .requiresApproval
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private struct AppleEchoTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let message: String
    }

    struct Output: Codable, Sendable {
        let echo: String
    }

    static let name = "echo"
    static let description = "Echoes the provided message."

    let counter: AppleToolCounter

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["message": .string(description: "Message to echo.")],
            required: ["message"]
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        await counter.increment()
        return Output(echo: arguments.message)
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private struct AppleImageTool: RichAgentTool {
    struct Arguments: Codable, Sendable {
        let message: String
    }

    static let name = "image_echo"
    static let description = "Returns image content."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["message": .string(description: "Message to echo.")],
            required: ["message"]
        ))
    }

    var capabilities: ToolCapabilities {
        ToolCapabilities(toolResultContentKinds: [.text, .image])
    }

    func execute(arguments: Arguments) async throws -> [ToolResultContent] {
        [
            .text(arguments.message),
            .image(mediaType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47])),
        ]
    }
}
private let appleApprovalAttemptCount = 10

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private struct AppleStructuredStreamAttempt {
    let sawToolStart: Bool
    let sawToolCompletion: Bool
    let result: AppleStructuredAnswer?
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func appleProviderFactory_isVisibleWhenFoundationModelsIsImportable() async throws {
    let provider = InferenceProvider.apple()
    let session: any InferenceSession = provider.makeSession(
        systemPrompt: "test", toolRuntime: testToolRuntime(), toolSelection: .all, inferenceContext: .empty
    )

    #expect(type(of: session) == AppleInferenceSession.self)
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func appleStructuredSessionFactory_returnsAppleInferenceSession() {
    let provider = InferenceProvider.apple()
    let session: any StructuredInferenceSession = provider.makeSession(
        systemPrompt: "test", toolRuntime: testToolRuntime(), toolSelection: .all, inferenceContext: .empty
    )

    #expect(type(of: session) == AppleInferenceSession.self)
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func appleStructuredGeneration_usesToolsWhenAvailable() async throws {
    guard case .available = SystemLanguageModel.default.availability else {
        return
    }

    for _ in 0..<appleApprovalAttemptCount {
        let (session, counter) = try makeAppleStructuredToolSession()

        let result: AppleStructuredAnswer = try await session.generate(
            prompt: "Use the tool and return the structured answer.",
            parameters: InferenceRequestParameters()
        )
        if await counter.value() == 1,
           result.answer.contains("structured-tool-test") {
            return
        }
    }

    Issue.record("Expected structured generation to use the echo tool across repeated attempts")
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func appleStructuredGenerationStream_emitsToolEventsWhenAvailable() async throws {
    guard case .available = SystemLanguageModel.default.availability else {
        return
    }

    for _ in 0..<appleApprovalAttemptCount {
        let (session, counter) = try makeAppleStructuredToolSession()

        let events = try await collectAppleStructuredStreamEvents(from: session)
        if await counter.value() == 1,
           events.sawToolStart,
           events.sawToolCompletion,
           events.result?.answer.contains("structured-tool-test") == true {
            return
        }
    }

    Issue.record("Expected structured generation stream to use the echo tool across repeated attempts")
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func appleProvider_rejectsImageProducingTools() async throws {
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(AppleImageTool())])
    )
    let provider = InferenceProvider.apple()
    do {
        try provider.preflight(toolRegistry: executor.registry, toolSelection: .all)
        Issue.record("Expected unsupportedConfiguration error for image-producing tool")
    } catch let error as InferenceError {
        guard case .unsupportedConfiguration(let message) = error else {
            Issue.record("Expected unsupportedConfiguration, got \(error)")
            return
        }
        #expect(message.contains("image_echo"))
    }
}
@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func appleAgentTurn_approvalRequiredResumesSameTurn() async throws {
    guard case .available = SystemLanguageModel.default.availability else {
        return
    }

    for _ in 0..<appleApprovalAttemptCount {
        let counter = AppleToolCounter()
        let session = makeAppleApprovalSession(
            counter: counter,
            message: "apple-agent-approved",
            afterToolGuidance: "After the tool returns, answer briefly."
        )
        let turn = try await session.send("Use the tool and respond.")
        var iterator = turn.events.makeAsyncIterator()
        guard let approval = try await nextAppleApprovalCallIfAny(from: &iterator) else {
            continue
        }

        try await session.approve(callID: approval.id)

        let postApproval = try await collectApplePostApprovalEvents(
            from: &iterator,
            approvalID: approval.id
        )

        #expect(await counter.value() == 1)
        #expect(postApproval.sawSuccessfulToolCompletion)
        #expect(postApproval.assistantCompletions == 1)
        return
    }

    withKnownIssue("Foundation Models may intermittently ignore tool-use instructions.") {
        Issue.record("Expected a tool approval request before stream completion")
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
@Test func appleAgentTurn_denialResumesSameTurnWithoutExecutingTool() async throws {
    guard case .available = SystemLanguageModel.default.availability else {
        return
    }

    for _ in 0..<appleApprovalAttemptCount {
        let counter = AppleToolCounter()
        let session = makeAppleApprovalSession(
            counter: counter,
            message: "apple-agent-denied",
            afterToolGuidance: "After the tool returns, answer briefly."
        )
        let turn = try await session.send("Use the tool and respond.")
        var iterator = turn.events.makeAsyncIterator()
        guard let approval = try await nextAppleApprovalCallIfAny(from: &iterator) else {
            continue
        }

        try await session.deny(callID: approval.id, reason: "blocked")

        var completion: ToolCallOutcome?
        while let event = try await iterator.next() {
            if case .toolCallCompleted(let name, let id, let outcome) = event.kind,
               name == AppleEchoTool.name,
               id == approval.id {
                completion = outcome
            }
        }

        #expect(await counter.value() == 0)
        #expect(completion == .failure(.denied(reason: "blocked")))
        return
    }

    withKnownIssue("Foundation Models may intermittently ignore tool-use instructions.") {
        Issue.record("Expected a tool approval request before stream completion")
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func nextAppleApprovalCallIfAny(
    from iterator: inout TurnEventStream<AssistantMessage>.AsyncIterator
) async throws -> PendingToolCall? {
    while let event = try await iterator.next() {
        if case .toolApprovalRequired(let call) = event.kind {
            return call
        }
    }
    return nil
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func makeAppleApprovalSession(
    counter: AppleToolCounter,
    message: String,
    afterToolGuidance: String
) -> AgentSession {
    let agent = Agent(
        providerRegistry: ProviderRegistry(default: InferenceProvider.apple()),
        behavior: .init(systemPrompt: """
        You must call the echo tool exactly once.
        Call it with message \(message).
        Do not provide any answer until after the tool call attempt completes.
        \(afterToolGuidance)
        """),
        toolDefinition: ToolDefinition(
            tools: [AnyAgentTool(AppleEchoTool(counter: counter))],
            executionPolicy: AppleRequiresApprovalPolicy()
        ),
    )
    return agent.makeSession()
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func collectApplePostApprovalEvents(
    from iterator: inout TurnEventStream<AssistantMessage>.AsyncIterator,
    approvalID: ToolCallID
) async throws -> (sawSuccessfulToolCompletion: Bool, assistantCompletions: Int) {
    var sawSuccessfulToolCompletion = false
    var assistantCompletions = 0
    while let event = try await iterator.next() {
        switch event.kind {
        case .toolCallCompleted(let name, let id, let outcome):
            if name == AppleEchoTool.name,
               id == approvalID,
               case .success = outcome {
                sawSuccessfulToolCompletion = true
            }
        case .result:
            assistantCompletions += 1
        default:
            break
        }
    }
    return (sawSuccessfulToolCompletion, assistantCompletions)
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func makeAppleStructuredToolSession() throws -> (some StructuredInferenceSession, AppleToolCounter) {
    let counter = AppleToolCounter()
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(AppleEchoTool(counter: counter))])
    )
    let provider = InferenceProvider.apple()
    try provider.preflight(toolRegistry: executor.registry, toolSelection: .all)
    let session = provider.makeSession(
        systemPrompt: """
        You must call the echo tool exactly once.
        Call it with message structured-tool-test.
        Return a JSON object whose answer is exactly the echoed message.
        """,
        toolRuntime: testToolRuntime(registry: executor.registry),
        toolSelection: .all,
        inferenceContext: .empty
    )
    return (session, counter)
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func collectAppleStructuredStreamEvents(
    from session: some StructuredInferenceSession
) async throws -> AppleStructuredStreamAttempt {
    let stream: StructuredInferenceStream<AppleStructuredAnswer> =
        try await session.generateStream(
            prompt: "Use the tool and return the structured answer.",
            parameters: InferenceRequestParameters()
        )

    var sawToolStart = false
    var sawToolCompletion = false
    var result: AppleStructuredAnswer?
    for try await event in stream {
        switch event {
        case .delta:
            Issue.record("Structured stream should not emit delta events")
        case .toolCallRequested(_, let name, _):
            sawToolStart = name == "echo"
        case .toolApprovalRequired:
            break
        case .toolCallCompleted(_, let name, let outcome):
            if case .success(let content) = outcome {
                sawToolCompletion = name == "echo" && !content.isEmpty
            }
        case .result(let structured, let reason):
            #expect(reason == .endTurn)
            result = structured
        case .toolHookFired:
            break
        }
    }
    return AppleStructuredStreamAttempt(
        sawToolStart: sawToolStart,
        sawToolCompletion: sawToolCompletion,
        result: result
    )
}

#endif
