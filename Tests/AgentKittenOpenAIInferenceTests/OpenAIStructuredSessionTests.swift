// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenCore
@testable import AgentKittenOpenAIInference
import Testing

@Suite("OpenAI structured generation")
struct OpenAIStructuredSessionTests {
    @Test("Decodes the model's JSON into the requested type")
    func decodesStructuredValue() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta(#"{"answer":"42"}"#), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        let value: OpenAIStructuredAnswer = try await session.generate(
            prompt: "What is 6 times 7?",
            parameters: InferenceRequestParameters(toolSelection: .disabled),
        )
        #expect(value == OpenAIStructuredAnswer(answer: "42"))
    }

    @Test("Injects the schema instruction into the system message")
    func injectsSchemaInstruction() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta(#"{"answer":"ok"}"#), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        let _: OpenAIStructuredAnswer = try await session.generate(
            prompt: "Answer",
            parameters: InferenceRequestParameters(toolSelection: .disabled),
        )
        let request = client.capturedRequests[0]
        #expect(request.messages.first?.role == .system)
        let system = request.messages.first?.content ?? ""
        #expect(system.contains("\"answer\""), "Expected the schema to be embedded in the system prompt.")
    }

    @Test("Runs tool calls before producing the final structured value")
    func runsToolCallsDuringStructuredGeneration() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "missing_tool", argsJSON: "{}"), .stopReason("tool_calls")],
            [.textDelta(#"{"answer":"done"}"#), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)

        var sawToolEvents = false
        var result: OpenAIStructuredAnswer?
        let stream: StructuredInferenceStream<OpenAIStructuredAnswer> = try await session.generateStream(
            prompt: "Use a tool then answer",
            parameters: InferenceRequestParameters(),
        )
        for try await event in stream {
            switch event {
            case .toolCallRequested, .toolCallCompleted:
                sawToolEvents = true
            case .result(let value, _):
                result = value
            default:
                break
            }
        }

        #expect(client.callCount == 2)
        #expect(sawToolEvents)
        #expect(result == OpenAIStructuredAnswer(answer: "done"))
    }

    @Test("Throws a decoding error when the model returns invalid JSON")
    func throwsOnInvalidJSON() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta("not json"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        await #expect(throws: StructuredGenerationError.self) {
            let _: OpenAIStructuredAnswer = try await session.generate(
                prompt: "Answer",
                parameters: InferenceRequestParameters(toolSelection: .disabled),
            )
        }
    }
}
#endif
