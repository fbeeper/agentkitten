// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

private let defaultExecutor = ToolExecutor(registry: ToolRegistry())
private let defaultToolRuntime = testToolRuntime()

@Test func mockSession_streamsResponse() async throws {
    let provider = MockInferenceProvider(responses: ["Hello world"])
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: defaultToolRuntime,
        toolSelection: .all,
        inferenceContext: .empty,
    )

    var chunks: [String] = []
    var didFinish = false

    let stream = try await session.run(UserMessage(text: "Hi"), parameters: InferenceRequestParameters())

    for try await event in stream {
        switch event {
        case .delta(let text):
            chunks.append(text)
        case .result(let text, let reason):
            #expect(text == "Hello world")
            #expect(reason == .endTurn)
            didFinish = true
        case .toolCallRequested, .toolApprovalRequired, .toolCallCompleted, .toolHookFired:
            break
        }
    }

    #expect(didFinish)
    let fullText = chunks.joined()
    #expect(fullText == "Hello world")
}

@Test func mockSession_cyclesThroughResponses() async throws {
    let provider = MockInferenceProvider(responses: ["First", "Second"])
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: defaultToolRuntime,
        toolSelection: .all,
        inferenceContext: .empty,
    )
    let message = UserMessage(text: "Hi")

    var text1 = ""
    for try await event in try await session.run(message, parameters: InferenceRequestParameters()) {
        if case .delta(let chunk) = event { text1 += chunk }
    }
    #expect(text1 == "First")

    var text2 = ""
    for try await event in try await session.run(message, parameters: InferenceRequestParameters()) {
        if case .delta(let chunk) = event { text2 += chunk }
    }
    #expect(text2 == "Second")
}

@Test func mockSession_throwsOnFailureResponse() async throws {
    let provider = MockInferenceProvider(mockResponses: [.failure(.streamInterrupted)])
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: defaultToolRuntime,
        toolSelection: .all,
        inferenceContext: .empty,
    )

    var caughtError: (any Error)?
    do {
        for try await _ in try await session.run(UserMessage(text: "Hi"), parameters: InferenceRequestParameters()) {}
    } catch {
        caughtError = error
    }

    #expect(caughtError as? InferenceError == .streamInterrupted)
}

@Test func mockSession_emptyResponsesFallback() async throws {
    // Neither init should crash; both should stream the default fallback text.
    let fromProvider = MockInferenceProvider(mockResponses: []).makeSession(
        systemPrompt: nil,
        toolRuntime: defaultToolRuntime,
        toolSelection: .all,
        inferenceContext: .empty,
    )
    let fromSession = MockInferenceSession(responses: [])
    for session in [fromProvider, fromSession] {
        var text = ""
        for try await event in try await session.run(
            UserMessage(text: "Hi"),
            parameters: InferenceRequestParameters(),
        ) {
            if case .delta(let chunk) = event { text += chunk }
        }
        #expect(text == "This is a mock response.")
    }
}

@Test func mockSession_propagatesProviderUnavailable() async throws {
    let provider = MockInferenceProvider(
        mockResponses: [.failure(.providerUnavailable("test backend offline"))],
    )
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: defaultToolRuntime,
        toolSelection: .all,
        inferenceContext: .empty,
    )

    var caughtError: (any Error)?
    do {
        for try await _ in try await session.run(UserMessage(text: "Hi"), parameters: InferenceRequestParameters()) {}
    } catch {
        caughtError = error
    }

    #expect(caughtError as? InferenceError == .providerUnavailable("test backend offline"))
}

struct MockStructuredValue: Codable, Sendable, JSONSchemaProviding, Equatable {
    let label: String

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "label": .string(description: "The generated label"),
            ],
            required: ["label"],
        )
    }
}

private struct MockEchoTool: AgentTool {
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
            properties: ["message": .string(description: "Message to echo.")],
            required: ["message"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(echo: arguments.message)
    }
}

@Test func mockSession_alsoConformsToStructuredInferenceSession() {
    let provider = MockInferenceProvider(
        responses: ["Hello world"],
        structuredResponses: [#"{"label":"structured"}"#],
    )
    let session: any StructuredInferenceSession = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: defaultToolRuntime,
        toolSelection: .all,
        inferenceContext: .empty,
    )

    #expect(type(of: session) == MockInferenceSession.self)
}

@Test func mockSession_generateDecodesStructuredResponses() async throws {
    let provider = MockInferenceProvider(
        responses: ["Hello world"],
        structuredResponses: [#"{"label":"structured"}"#],
    )
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: defaultToolRuntime,
        toolSelection: .all,
        inferenceContext: .empty,
    )

    let value: MockStructuredValue = try await session.generate(
        prompt: "Return a label",
        parameters: InferenceRequestParameters(),
    )
    #expect(value == MockStructuredValue(label: "structured"))
}

@Test func mockSession_generateSupportsStructuredToolCallScripts() async throws {
    let provider = MockInferenceProvider(
        mockResponses: ["Hello world"].map { .success($0) },
        structuredMockResponses: [
            .toolCall(
                name: "echo",
                argumentsJSON: #"{"message":"structured"}"#,
                thenRespond: #"{"label":"structured"}"#,
            ),
        ],
    )
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(MockEchoTool())]),
    )
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: testToolRuntime(registry: executor.registry),
        toolSelection: .all,
    )

    let value: MockStructuredValue = try await session.generate(
        prompt: "Return a label",
        parameters: InferenceRequestParameters(),
    )
    #expect(value == MockStructuredValue(label: "structured"))
}

@Test func mockSession_generateStreamEmitsToolAndTextEvents() async throws {
    let provider = MockInferenceProvider(
        mockResponses: ["Hello world"].map { .success($0) },
        structuredMockResponses: [
            .toolCall(
                name: "echo",
                argumentsJSON: #"{"message":"structured"}"#,
                thenRespond: #"{"label":"structured"}"#,
            ),
        ],
    )
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(MockEchoTool())]),
    )
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: testToolRuntime(registry: executor.registry),
        toolSelection: .all,
    )

    let stream: StructuredInferenceStream<MockStructuredValue> =
        try await session.generateStream(
            prompt: "Return a label", parameters: InferenceRequestParameters(),
        )

    var sawToolStart = false
    var sawToolCompletion = false
    var text = ""
    var value: MockStructuredValue?
    for try await event in stream {
        switch event {
        case .delta(let chunk):
            text += chunk
        case .toolCallRequested(_, let name, _):
            sawToolStart = name == "echo"
        case .toolApprovalRequired:
            break
        case .toolCallCompleted(_, let name, let outcome):
            if case .success(let content) = outcome {
                sawToolCompletion = name == "echo" && content == [.text(#"{"echo":"structured"}"#)]
            }
        case .result(let structured, let reason):
            #expect(reason == .endTurn)
            value = structured
        case .toolHookFired:
            break
        }
    }

    #expect(sawToolStart)
    #expect(sawToolCompletion)
    #expect(text.isEmpty)
    #expect(value == MockStructuredValue(label: "structured"))
}

@Test func mockSession_disabledToolSelectionDeniesToolAndContinuesTextTurn() async throws {
    let provider = MockInferenceProvider(
        mockResponses: [
            .toolCall(
                name: "echo",
                argumentsJSON: #"{"message":"blocked"}"#,
                thenRespond: "Done.",
            ),
        ],
    )
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(MockEchoTool())]),
    )
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: testToolRuntime(registry: executor.registry),
        toolSelection: .all,
    )

    var outcome: ToolCallOutcome?
    var resultText: String?
    for try await event in try await session.run(
        UserMessage(text: "Hi"),
        parameters: InferenceRequestParameters(toolSelection: .disabled),
    ) {
        switch event {
        case .toolCallCompleted(_, _, let completed):
            outcome = completed
        case .result(let text, _):
            resultText = text
        default:
            break
        }
    }

    #expect(outcome == .failure(.denied(reason: "tools disabled")))
    #expect(resultText == "Done.")
}

@Test func mockSession_disabledToolSelectionDeniesToolAndContinuesStructuredTurn() async throws {
    let provider = MockInferenceProvider(
        mockResponses: ["Hello world"].map { .success($0) },
        structuredMockResponses: [
            .toolCall(
                name: "echo",
                argumentsJSON: #"{"message":"blocked"}"#,
                thenRespond: #"{"label":"structured"}"#,
            ),
        ],
    )
    let executor = ToolExecutor(
        registry: ToolRegistry([AnyAgentTool(MockEchoTool())]),
    )
    let session = provider.makeSession(
        systemPrompt: nil,
        toolRuntime: testToolRuntime(registry: executor.registry),
        toolSelection: .all,
    )

    let stream: StructuredInferenceStream<MockStructuredValue> =
        try await session.generateStream(
            prompt: "Return a label",
            parameters: InferenceRequestParameters(toolSelection: .disabled),
        )

    var outcome: ToolCallOutcome?
    var value: MockStructuredValue?
    for try await event in stream {
        switch event {
        case .toolCallCompleted(_, _, let completed):
            outcome = completed
        case .result(let structured, _):
            value = structured
        default:
            break
        }
    }

    #expect(outcome == .failure(.denied(reason: "tools disabled")))
    #expect(value == MockStructuredValue(label: "structured"))
}
