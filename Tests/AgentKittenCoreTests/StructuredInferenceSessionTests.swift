// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

// MARK: - Test fixture

private struct TaskClassification: Codable, Sendable, JSONSchemaProviding {
    let complexity: String
    let estimatedSteps: Int

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "complexity": .string(description: "low, medium, or high"),
                "estimatedSteps": .integer(description: "Estimated number of steps"),
            ],
            required: ["complexity", "estimatedSteps"],
        )
    }
}

// MARK: - Suite

@Suite("StructuredInferenceSession")
struct StructuredInferenceSessionTests {
    // MARK: JSONSchemaProviding

    @Test func jsonSchemaProviding_staticPropertyAccessible() {
        let schema = TaskClassification.jsonSchema
        guard case .object(let properties, let required) = schema else {
            Issue.record("Expected .object schema")
            return
        }
        #expect(properties.keys.contains("complexity"))
        #expect(properties.keys.contains("estimatedSteps"))
        #expect(required == ["complexity", "estimatedSteps"])
    }

    @Test func jsonSchemaProviding_arrayConformanceWrapsElementSchema() {
        let schema = [TaskClassification].jsonSchema
        guard case .array(let items, let description) = schema else {
            Issue.record("Expected .array schema")
            return
        }
        #expect(description == nil)
        guard case .object(let properties, let required) = items else {
            Issue.record("Expected array element schema to be an object")
            return
        }
        #expect(properties.keys.contains("complexity"))
        #expect(properties.keys.contains("estimatedSteps"))
        #expect(required == ["complexity", "estimatedSteps"])
    }

    // MARK: MockInferenceSession

    @Test func mockInferenceSession_generateThrowsGenerationFailedWhenEmpty() async {
        let session = MockInferenceSession(responses: [])
        do {
            let _: TaskClassification = try await session.generate(
                prompt: "test",
                parameters: InferenceRequestParameters(),
            )
            Issue.record("Expected StructuredGenerationError.generationFailed")
        } catch StructuredGenerationError.generationFailed {
            // Expected path.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: MockInferenceProvider

    @Test func mockProvider_makeStructuredSessionReturnsSession() {
        let provider = MockInferenceProvider()
        let session: MockInferenceSession = provider.makeSession(
            systemPrompt: nil,
            toolRuntime: testToolRuntime(),
            toolSelection: .all,
        )
        _ = session
    }

    // MARK: InferenceProvider wrapper

    @Test func inferenceProviderWrapper_makeStructuredSessionCompiles() {
        let provider = InferenceProvider.mock()
        let session: MockInferenceSession = provider.makeSession(
            systemPrompt: nil,
            toolRuntime: testToolRuntime(),
            toolSelection: .all,
        )
        _ = session
    }

    @Test func inferenceProviderWrapper_makeStructuredSessionWithSystemPrompt() {
        let provider = InferenceProvider.mock()
        let session: MockInferenceSession = provider.makeSession(
            systemPrompt: "You are a classifier.",
            toolRuntime: testToolRuntime(),
            toolSelection: .all,
        )
        _ = session
    }
}
