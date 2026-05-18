// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
@testable import AgentKittenInference
import Foundation
import Testing

// MARK: - Test fixture

private struct Sentiment: Codable, Sendable, JSONSchemaProviding, Equatable {
    let label: String
    let confidence: Double

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "label": .string(description: "positive, negative, or neutral"),
                "confidence": .number(description: "0.0 to 1.0"),
            ],
            required: ["label", "confidence"],
        )
    }
}

// MARK: - Capturing mock client

/// Records the last request it received and returns pre-configured SSE events.
private final class CapturingHTTPClient: AnthropicHTTPStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var _capturedRequest: AnthropicRequest?
    private let events: [SSEEvent]

    var capturedRequest: AnthropicRequest? {
        lock.withLock { _capturedRequest }
    }

    init(events: [SSEEvent]) {
        self.events = events
    }

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        lock.withLock { _capturedRequest = request }
        let events = events
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

/// Always throws the given error when `stream(request:)` is called.
private struct ThrowingHTTPClient: AnthropicHTTPStreaming {
    let error: any Error

    func stream(request: AnthropicRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        let error = error
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

// MARK: - Helpers

private func makeSession(
    systemPrompt: String? = nil,
    registry: ToolRegistry = ToolRegistry(),
    toolExecutionPolicy: some ToolExecutionPolicy = AutoApprovePolicy(),
    client: some AnthropicHTTPStreaming,
) -> AnthropicInferenceSession {
    AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "test-model",
        systemPrompt: systemPrompt,
        toolRuntime: testToolRuntime(registry: registry, executionPolicy: toolExecutionPolicy),
        clientFactory: { _ in client },
    )
}

// MARK: - Suite

@Suite("Anthropic Structured Generation", .serialized)
struct AnthropicStructuredSessionTests {
    // MARK: Successful decode

    @Test func generate_decodesValidJSON() async throws {
        let json = #"{"label":"positive","confidence":0.95}"#
        let client = CapturingHTTPClient(events: [
            .textDelta(json),
            .stopReason("end_turn"),
        ])
        let session = makeSession(client: client)

        let result: Sentiment = try await session.generate(
            prompt: "Classify this.",
            parameters: InferenceRequestParameters(),
        )
        #expect(result.label == "positive")
        #expect(result.confidence == 0.95)
    }

    @Test func generate_decodesResponseSplitAcrossMultipleDeltas() async throws {
        let client = CapturingHTTPClient(events: [
            .textDelta(#"{"label":"ne"#),
            .textDelta(#"gative","confidence":"#),
            .textDelta(#"0.3}"#),
            .stopReason("end_turn"),
        ])
        let session = makeSession(client: client)

        let result: Sentiment = try await session.generate(
            prompt: "Classify this.",
            parameters: InferenceRequestParameters(),
        )
        #expect(result.label == "negative")
        #expect(result.confidence == 0.3)
    }

    @Test func generate_decodesTopLevelArrayJSON() async throws {
        let json = #"[{"label":"positive","confidence":0.95},{"label":"neutral","confidence":0.5}]"#
        let client = CapturingHTTPClient(events: [
            .textDelta(json),
            .stopReason("end_turn"),
        ])
        let session = makeSession(client: client)

        let result: [Sentiment] = try await session.generate(
            prompt: "Classify these items.",
            parameters: InferenceRequestParameters(),
        )
        #expect(result == [
            Sentiment(label: "positive", confidence: 0.95),
            Sentiment(label: "neutral", confidence: 0.5),
        ])
    }

    // MARK: Error paths

    @Test func generate_throwsDecodingFailedForInvalidJSON() async {
        let client = CapturingHTTPClient(events: [
            .textDelta("not valid json at all"),
            .stopReason("end_turn"),
        ])
        let session = makeSession(client: client)

        do {
            let _: Sentiment = try await session.generate(
                prompt: "Classify this.",
                parameters: InferenceRequestParameters(),
            )
            Issue.record("Expected StructuredGenerationError.decodingFailed")
        } catch StructuredGenerationError.decodingFailed {
            // Expected path.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func generate_preservesInferenceErrorForStreamError() async {
        let client = ThrowingHTTPClient(error: InferenceError.streamInterrupted)
        let session = makeSession(client: client)

        do {
            let _: Sentiment = try await session.generate(
                prompt: "Classify this.",
                parameters: InferenceRequestParameters(),
            )
            Issue.record("Expected InferenceError.streamInterrupted")
        } catch InferenceError.streamInterrupted {
            // Expected path.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func generate_preservesInferenceErrorForAPIError() async {
        let client = CapturingHTTPClient(events: [
            .error("rate limit exceeded"),
        ])
        let session = makeSession(client: client)

        do {
            let _: Sentiment = try await session.generate(
                prompt: "Classify this.",
                parameters: InferenceRequestParameters(),
            )
            Issue.record("Expected InferenceError.invalidResponse")
        } catch InferenceError.invalidResponse(let message) {
            #expect(message == "rate limit exceeded")
            // Expected path.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: Request shape

    @Test func generate_injectsSchemaIntoSystemPrompt() async throws {
        let client = CapturingHTTPClient(events: [
            .textDelta(#"{"label":"neutral","confidence":0.5}"#),
            .stopReason("end_turn"),
        ])
        let session = makeSession(systemPrompt: "You are a classifier.", client: client)
        let _: Sentiment = try await session.generate(
            prompt: "test", parameters: InferenceRequestParameters(),
        )

        let request = try #require(client.capturedRequest)
        let system = try #require(request.system)
        #expect(system.contains("You are a classifier."))
        #expect(system.contains("single valid JSON value"))
        #expect(
            system.contains(
                "When the root schema is an object, start with { and end with }; " +
                    "when it is an array, start with [ and end with ].",
            ),
        )
        #expect(system.contains("label"))
        #expect(system.contains("confidence"))
    }

    @Test func generate_includesNoToolsWhenNoneRegistered() async throws {
        let client = CapturingHTTPClient(events: [
            .textDelta(#"{"label":"neutral","confidence":0.5}"#),
            .stopReason("end_turn"),
        ])
        let session = makeSession(client: client)
        let _: Sentiment = try await session.generate(
            prompt: "test", parameters: InferenceRequestParameters(),
        )

        let request = try #require(client.capturedRequest)
        #expect(request.tools == nil)
    }

    @Test func generate_usesZeroTemperature() async throws {
        let client = CapturingHTTPClient(events: [
            .textDelta(#"{"label":"neutral","confidence":0.5}"#),
            .stopReason("end_turn"),
        ])
        let session = makeSession(client: client)
        let _: Sentiment = try await session.generate(
            prompt: "test", parameters: InferenceRequestParameters(),
        )

        let request = try #require(client.capturedRequest)
        #expect(request.temperature == 0)
    }

    @Test func generate_includesRegisteredToolsInRequest() async throws {
        let client = CapturingHTTPClient(events: [
            .textDelta(#"{"label":"neutral","confidence":0.5}"#),
            .stopReason("end_turn"),
        ])
        let registry = ToolRegistry([AnyAgentTool(InferenceEchoTool())])
        let session = makeSession(registry: registry, client: client)
        let _: Sentiment = try await session.generate(
            prompt: "test",
            parameters: InferenceRequestParameters(toolSelection: .all),
        )

        let request = try #require(client.capturedRequest)
        #expect(request.tools != nil)
    }

    @Test func generate_suppressesToolsWhenToolsAllowedFalse() async throws {
        let client = CapturingHTTPClient(events: [
            .textDelta(#"{"label":"neutral","confidence":0.5}"#),
            .stopReason("end_turn"),
        ])
        let registry = ToolRegistry([AnyAgentTool(InferenceEchoTool())])
        let session = makeSession(registry: registry, client: client)
        let _: Sentiment = try await session.generate(
            prompt: "test",
            parameters: InferenceRequestParameters(toolSelection: .disabled),
        )

        let request = try #require(client.capturedRequest)
        #expect(request.tools == nil)
    }

    @Test func generate_usesCustomInstructionFormatForStructuredOutput() async throws {
        let client = CapturingHTTPClient(events: [
            .textDelta(#"{"label":"neutral","confidence":0.5}"#),
            .stopReason("end_turn"),
        ])
        let customFormat =
            "CUSTOM TEST SCHEMA:\n%@\nRETURN RAW JSON VALUE. OBJECT ROOT -> START { END }. ARRAY ROOT -> START [ END ]."
        let session = AnthropicInferenceSession(
            credentials: MockAPIKeyProvider("test-key"),
            defaultModel: "test-model",
            systemPrompt: nil,
            toolRuntime: testToolRuntime(),
            structuredOutputInstructionFormat: customFormat,
            clientFactory: { _ in client },
        )
        let _: Sentiment = try await session.generate(
            prompt: "test",
            parameters: InferenceRequestParameters(toolSelection: .disabled),
        )
        let request = try #require(client.capturedRequest)
        #expect(request.system?.contains("CUSTOM TEST SCHEMA:") == true)
        #expect(request.system?.contains("RETURN RAW JSON VALUE.") == true)
        #expect(request.system?.contains("OBJECT ROOT -> START { END }.") == true)
        #expect(request.system?.contains("ARRAY ROOT -> START [ END ].") == true)
    }

    @Test func generate_filtersRegisteredToolsBySelection() async throws {
        let client = CapturingHTTPClient(events: [
            .textDelta(#"{"label":"neutral","confidence":0.5}"#),
            .stopReason("end_turn"),
        ])
        let registry = ToolRegistry([
            AnyAgentTool(InferenceEchoTool()),
            AnyAgentTool(InferenceWeatherTool()),
        ])
        let session = makeSession(registry: registry, client: client)
        let _: Sentiment = try await session.generate(
            prompt: "test",
            parameters: InferenceRequestParameters(toolSelection: .excluding(["weather"])),
        )

        let request = try #require(client.capturedRequest)
        #expect(request.tools?.map(\.name).sorted() == ["echo"])
    }
}
