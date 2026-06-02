// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenCore
import AgentKittenInferenceSupport
@testable import AgentKittenOpenAIInference
import Foundation
import Testing

@Suite("OpenAI text session")
struct OpenAISessionTests {
    private struct TurnOutput {
        var deltas = ""
        var result: String?
        var finish: FinishReason?
    }

    private func collectText(
        _ session: OpenAIInferenceSession,
        _ message: String,
        parameters: InferenceRequestParameters = InferenceRequestParameters(toolSelection: .disabled),
    ) async throws -> TurnOutput {
        var output = TurnOutput()
        for try await event in try await session.run(UserMessage(text: message), parameters: parameters) {
            switch event {
            case .delta(let chunk):
                output.deltas += chunk
            case .result(let text, let reason):
                output.result = text
                output.finish = reason
            default:
                break
            }
        }
        return output
    }

    @Test("Streams text deltas and a terminal result")
    func streamsText() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta("Hello "), .textDelta("world"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        let output = try await collectText(session, "Hi")
        #expect(output.deltas == "Hello world")
        #expect(output.result == "Hello world")
        #expect(output.finish == .endTurn)
    }

    @Test("Calls the client once per turn")
    func callsClientOncePerTurn() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta("first"), .stopReason("stop")],
            [.textDelta("second"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        _ = try await collectText(session, "First")
        _ = try await collectText(session, "Second")
        #expect(client.callCount == 2)
    }

    @Test("Maps length finish reason to maxTokens")
    func mapsLengthFinishReason() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta("partial"), .stopReason("length")],
        ])
        let session = makeOpenAITestSession(client: client)
        let output = try await collectText(session, "Hi")
        #expect(output.finish == .maxTokens)
    }

    @Test("Carries prior turns and system prompt into the next request")
    func accumulatesHistory() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta("first"), .stopReason("stop")],
            [.textDelta("second"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client, systemPrompt: "Be brief.")
        _ = try await collectText(session, "one")
        _ = try await collectText(session, "two")

        let secondRequest = client.capturedRequests[1]
        let roles = secondRequest.messages.map(\.role)
        // system + user(one) + assistant(first) + user(two)
        #expect(roles == [.system, .user, .assistant, .user])
    }

    @Test("Preserves empty assistant turn in request history")
    func preservesEmptyAssistantTurn() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.stopReason("stop")],
            [.textDelta("second"), .stopReason("stop")],
        ])
        let session = makeOpenAITestSession(client: client)
        _ = try await collectText(session, "one")
        _ = try await collectText(session, "two")

        let secondRequest = client.capturedRequests[1]
        let roles = secondRequest.messages.map(\.role)
        #expect(roles == [.user, .assistant, .user])
        #expect(secondRequest.messages[1].content == "")
    }

    @Test("Surfaces an error event as a thrown error")
    func surfacesError() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.error("rate limited")],
        ])
        let session = makeOpenAITestSession(client: client)
        await #expect(throws: InferenceError.self) {
            _ = try await collectText(session, "Hi")
        }
    }

    @Test("Structured output is unsupported in the text-only session")
    func structuredUnsupported() async throws {
        let client = MockOpenAIHTTPClient(responses: [[.textDelta("x"), .stopReason("stop")]])
        let session = makeOpenAITestSession(client: client)
        await #expect(throws: InferenceError.self) {
            let _: OpenAIStructuredAnswer = try await session.generate(
                prompt: "answer",
                parameters: InferenceRequestParameters(toolSelection: .disabled),
            )
        }
    }
}

private struct OpenAIStructuredAnswer: Codable, Sendable, JSONSchemaProviding {
    let answer: String

    static var jsonSchema: JSONSchema {
        .object(properties: ["answer": .string(description: "The answer.")], required: ["answer"])
    }
}
#endif
