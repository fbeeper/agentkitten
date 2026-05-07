// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore

private struct Label: Codable, Sendable, JSONSchemaProviding, Equatable {
    let name: String
    let score: Double

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "name": .string(description: "The label name"),
                "score": .number(description: "Confidence score"),
            ],
            required: ["name", "score"]
        )
    }
}

@Suite("Mock Structured Generation")
struct MockStructuredSessionTests {

    // MARK: No responses configured

    @Test func generate_throwsGenerationFailedWhenNoResponses() async {
        let session = MockInferenceSession(responses: [])
        do {
            let _: Label = try await session.generate(prompt: "test", parameters: InferenceRequestParameters())
            Issue.record("Expected .generationFailed")
        } catch StructuredGenerationError.generationFailed {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: Successful decode

    @Test func generate_decodesValidJSON() async throws {
        let session = MockInferenceSession(
            responses: [],
            structuredResponses: [#"{"name":"urgent","score":0.95}"#]
        )
        let result: Label = try await session.generate(prompt: "test", parameters: InferenceRequestParameters())
        #expect(result.name == "urgent")
        #expect(result.score == 0.95)
    }

    @Test func generate_cyclesThroughResponses() async throws {
        let session = MockInferenceSession(
            responses: [],
            structuredResponses: [
                #"{"name":"first","score":0.1}"#,
                #"{"name":"second","score":0.2}"#,
            ]
        )

        let first: Label = try await session.generate(prompt: "test", parameters: InferenceRequestParameters())
        let second: Label = try await session.generate(prompt: "test", parameters: InferenceRequestParameters())
        let third: Label = try await session.generate(prompt: "test", parameters: InferenceRequestParameters())

        #expect(first.name == "first")
        #expect(second.name == "second")
        #expect(third.name == "first")  // wraps around
    }

    @Test func generate_decodesTopLevelArrayJSON() async throws {
        let session = MockInferenceSession(
            responses: [],
            structuredResponses: [#"[{"name":"urgent","score":0.95},{"name":"park","score":0.8}]"#]
        )
        let result: [Label] = try await session.generate(prompt: "test", parameters: InferenceRequestParameters())
        #expect(result == [
            Label(name: "urgent", score: 0.95),
            Label(name: "park", score: 0.8),
        ])
    }

    // MARK: Error paths

    @Test func generate_throwsDecodingFailedForInvalidJSON() async {
        let session = MockInferenceSession(
            responses: [],
            structuredResponses: ["not json"]
        )
        do {
            let _: Label = try await session.generate(prompt: "test", parameters: InferenceRequestParameters())
            Issue.record("Expected .decodingFailed")
        } catch StructuredGenerationError.decodingFailed {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: MockInferenceProvider integration

    @Test func provider_passesStructuredResponsesToSession() async throws {
        let provider = MockInferenceProvider(
            structuredResponses: [#"{"name":"positive","score":0.8}"#]
        )
        let session = provider.makeSession(
            systemPrompt: nil,
            toolRuntime: testToolRuntime(),
            toolSelection: .all,
            inferenceContext: .empty
        )
        let result: Label = try await session.generate(prompt: "test", parameters: InferenceRequestParameters())
        #expect(result.name == "positive")
    }

    @Test func provider_defaultStructuredSessionThrowsGenerationFailed() async {
        let provider = MockInferenceProvider()
        let session = provider.makeSession(
            systemPrompt: nil,
            toolRuntime: testToolRuntime(),
            toolSelection: .all,
            inferenceContext: .empty
        )
        do {
            let _: Label = try await session.generate(prompt: "test", parameters: InferenceRequestParameters())
            Issue.record("Expected .generationFailed")
        } catch StructuredGenerationError.generationFailed {
            // Expected — no structured responses configured.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
