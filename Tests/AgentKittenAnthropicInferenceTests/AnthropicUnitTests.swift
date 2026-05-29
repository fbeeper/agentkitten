// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation
import Testing

// MARK: - InferenceProviderJSONValue.encoding schema cases

@Suite("InferenceProviderJSONValue encoding from JSONSchema")
struct JSONValueEncodingSchemaTests {
    @Test func string_withDescription_includesDescriptionKey() {
        let result = InferenceProviderJSONValue.encoding(.string(description: "A name."))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("string"))
        #expect(dict["description"] == .string("A name."))
    }

    @Test func string_nilDescription_omitsDescriptionKey() {
        let result = InferenceProviderJSONValue.encoding(.string(description: nil))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["description"] == nil)
    }

    @Test func integer_mapsToIntegerType() {
        let result = InferenceProviderJSONValue.encoding(.integer(description: nil))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("integer"))
    }

    @Test func number_mapsToNumberType() {
        let result = InferenceProviderJSONValue.encoding(.number(description: "Score."))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("number"))
        #expect(dict["description"] == .string("Score."))
    }

    @Test func boolean_mapsToBooleanType() {
        let result = InferenceProviderJSONValue.encoding(.boolean(description: nil))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("boolean"))
    }

    @Test func array_includesItemsAndType() {
        let result = InferenceProviderJSONValue.encoding(.array(items: .string(description: nil), description: "Tags."))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("array"))
        #expect(dict["items"] != nil)
        #expect(dict["description"] == .string("Tags."))
    }

    @Test func array_nilDescription_omitsDescriptionKey() {
        let result = InferenceProviderJSONValue.encoding(.array(items: .integer(description: nil), description: nil))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["description"] == nil)
    }

    @Test func enumeration_includesEnumArray() {
        let result = InferenceProviderJSONValue.encoding(.enumeration(values: ["fast", "slow"], description: "Speed."))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("string"))
        #expect(dict["enum"] == .array([.string("fast"), .string("slow")]))
        #expect(dict["description"] == .string("Speed."))
    }

    @Test func enumeration_nilDescription_omitsDescriptionKey() {
        let result = InferenceProviderJSONValue.encoding(.enumeration(values: ["a"], description: nil))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["description"] == nil)
    }

    @Test func object_emptyRequired_omitsRequiredKey() {
        let result = InferenceProviderJSONValue.encoding(
            .object(properties: ["x": .string(description: nil)], required: []),
        )
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["required"] == nil)
    }

    @Test func object_withRequired_includesRequiredArray() {
        let result = InferenceProviderJSONValue.encoding(
            .object(properties: ["x": .string(description: nil)], required: ["x"]),
        )
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["required"] == .array([.string("x")]))
    }
}

// MARK: - InferenceProviderJSONValue: Decodable

@Suite("InferenceProviderJSONValue Decodable")
struct JSONValueDecodableTests {
    private func decode(_ json: String) throws -> InferenceProviderJSONValue {
        try JSONDecoder().decode(InferenceProviderJSONValue.self, from: Data(json.utf8))
    }

    @Test func string() throws {
        #expect(try decode(#""hello""#) == .string("hello"))
    }

    @Test func bool_true() throws {
        #expect(try decode("true") == .bool(true))
    }

    @Test func bool_false() throws {
        #expect(try decode("false") == .bool(false))
    }

    @Test func number_double() throws {
        #expect(try decode("3.14") == .number(3.14))
    }

    @Test func null() throws {
        #expect(try decode("null") == .null)
    }

    @Test func array() throws {
        #expect(try decode(#"["a","b"]"#) == .array([.string("a"), .string("b")]))
    }

    @Test func object() throws {
        #expect(try decode(#"{"key":"val"}"#) == .object(["key": .string("val")]))
    }
}

// MARK: - AnthropicModels: AnthropicModelContextWindow

@Suite("AnthropicModelContextWindow")
struct AnthropicModelContextWindowTests {
    @Test func claudeModel_returns200k() {
        #expect(AnthropicModelContextWindow.standardMaxInputTokens(for: "claude-sonnet-4-5") == 200_000)
    }

    @Test func nonClaudeModel_returnsNil() {
        #expect(AnthropicModelContextWindow.standardMaxInputTokens(for: "gpt-4") == nil)
    }
}

// MARK: - AnthropicContent: isErrorToolResult

@Suite("AnthropicContent isErrorToolResult")
struct AnthropicContentIsErrorTests {
    @Test func toolResult_withError_returnsTrue() {
        let content = AnthropicContent.toolResult(toolUseID: "id", content: [], isError: true)
        #expect(content.isErrorToolResult)
    }

    @Test func toolResult_withoutError_returnsFalse() {
        let content = AnthropicContent.toolResult(toolUseID: "id", content: [], isError: false)
        #expect(!content.isErrorToolResult)
    }

    @Test func text_returnsFalse() {
        #expect(!AnthropicContent.text("hi").isErrorToolResult)
    }
}

// MARK: - AnthropicInferenceProvider: sessionCompatibility

@Suite("AnthropicInferenceProvider sessionCompatibility")
struct AnthropicSessionCompatibilityTests {
    private let provider = AnthropicInferenceProvider(credentials: MockAPIKeyProvider("k"))

    @Test func identicalConfigs_reuse() {
        let cfg = EffectiveExecutionConfiguration()
        #expect(provider.sessionCompatibility(from: cfg, to: cfg) == .reuse)
    }

    @Test func toolSelectionChange_stillReuses() {
        // Anthropic gates tools per-request, not per-session.
        let result = provider.sessionCompatibility(
            from: EffectiveExecutionConfiguration(toolSelection: .all),
            to: EffectiveExecutionConfiguration(toolSelection: .disabled),
        )
        #expect(result == .reuse)
    }

    @Test func providerChange_replaces() {
        let result = provider.sessionCompatibility(
            from: EffectiveExecutionConfiguration(provider: .default),
            to: EffectiveExecutionConfiguration(provider: .ofType(AnthropicInferenceProvider.self)),
        )
        #expect(result == .replace)
    }
}

// MARK: - InferenceProvider+Anthropic factory methods

@Suite("InferenceProvider+Anthropic factories")
struct AnthropicFactoryTests {
    @Test func anthropic_defaultFactory_createsProvider() {
        let provider = InferenceProvider.anthropic()
        let session = provider.makeSession(
            systemPrompt: nil,
            toolRuntime: testToolRuntime(),
            toolSelection: .all,
            inferenceContext: .empty,
        )
        #expect(type(of: session) == AnthropicInferenceSession.self)
    }

    @Test func anthropic_customModel_createsProvider() {
        let provider = InferenceProvider.anthropic(model: "claude-opus-4-7")
        let session = provider.makeSession(
            systemPrompt: nil,
            toolRuntime: testToolRuntime(),
            toolSelection: .all,
            inferenceContext: .empty,
        )
        #expect(type(of: session) == AnthropicInferenceSession.self)
    }

    #if canImport(Security)
    @Test func anthropic_keychainFactory_createsProvider() {
        let provider = InferenceProvider.anthropic(keychain: "com.example.app", account: "anthropic")
        let session = provider.makeSession(
            systemPrompt: nil,
            toolRuntime: testToolRuntime(),
            toolSelection: .all,
            inferenceContext: .empty,
        )
        #expect(type(of: session) == AnthropicInferenceSession.self)
    }
    #endif
}
#endif
