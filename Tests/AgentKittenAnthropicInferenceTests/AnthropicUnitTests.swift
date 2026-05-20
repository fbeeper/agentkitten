// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenAnthropicInference
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation
import Testing

// MARK: - AnthropicToolBridge: anthropicJSONValue schema cases

@Suite("AnthropicToolBridge anthropicJSONValue")
struct AnthropicToolBridgeSchemaTests {
    @Test func string_withDescription_includesDescriptionKey() {
        let result = AnthropicToolBridge.anthropicJSONValue(from: .string(description: "A name."))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("string"))
        #expect(dict["description"] == .string("A name."))
    }

    @Test func string_nilDescription_omitsDescriptionKey() {
        let result = AnthropicToolBridge.anthropicJSONValue(from: .string(description: nil))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["description"] == nil)
    }

    @Test func integer_mapsToIntegerType() {
        let result = AnthropicToolBridge.anthropicJSONValue(from: .integer(description: nil))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("integer"))
    }

    @Test func number_mapsToNumberType() {
        let result = AnthropicToolBridge.anthropicJSONValue(from: .number(description: "Score."))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("number"))
        #expect(dict["description"] == .string("Score."))
    }

    @Test func boolean_mapsToBooleanType() {
        let result = AnthropicToolBridge.anthropicJSONValue(from: .boolean(description: nil))
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("boolean"))
    }

    @Test func array_includesItemsAndType() {
        let result = AnthropicToolBridge.anthropicJSONValue(
            from: .array(items: .string(description: nil), description: "Tags."),
        )
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("array"))
        #expect(dict["items"] != nil)
        #expect(dict["description"] == .string("Tags."))
    }

    @Test func array_nilDescription_omitsDescriptionKey() {
        let result = AnthropicToolBridge.anthropicJSONValue(
            from: .array(items: .integer(description: nil), description: nil),
        )
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["description"] == nil)
    }

    @Test func enumeration_includesEnumArray() {
        let result = AnthropicToolBridge.anthropicJSONValue(
            from: .enumeration(values: ["fast", "slow"], description: "Speed."),
        )
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["type"] == .string("string"))
        #expect(dict["enum"] == .array([.string("fast"), .string("slow")]))
        #expect(dict["description"] == .string("Speed."))
    }

    @Test func enumeration_nilDescription_omitsDescriptionKey() {
        let result = AnthropicToolBridge.anthropicJSONValue(
            from: .enumeration(values: ["a"], description: nil),
        )
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["description"] == nil)
    }

    @Test func object_emptyRequired_omitsRequiredKey() {
        let result = AnthropicToolBridge.anthropicJSONValue(
            from: .object(properties: ["x": .string(description: nil)], required: []),
        )
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["required"] == nil)
    }

    @Test func object_withRequired_includesRequiredArray() {
        let result = AnthropicToolBridge.anthropicJSONValue(
            from: .object(properties: ["x": .string(description: nil)], required: ["x"]),
        )
        guard case .object(let dict) = result else {
            Issue.record("Expected object"); return
        }
        #expect(dict["required"] == .array([.string("x")]))
    }
}

// MARK: - AnthropicJSONValue: init from raw Any

@Suite("AnthropicJSONValue init(raw:)")
struct AnthropicJSONValueInitTests {
    @Test func string_fromNSString() {
        #expect(AnthropicJSONValue("hello" as NSString) == .string("hello"))
    }

    @Test func bool_fromNSNumber_true() {
        #expect(AnthropicJSONValue(true as NSNumber) == .bool(true))
    }

    @Test func bool_fromNSNumber_false() {
        #expect(AnthropicJSONValue(false as NSNumber) == .bool(false))
    }

    @Test func number_fromNSNumber_double() {
        #expect(AnthropicJSONValue(3.14 as NSNumber) == .number(3.14))
    }

    @Test func null_fromUnknownType() {
        #expect(AnthropicJSONValue(NSObject()) == .null)
    }

    @Test func array_fromNSArray() {
        let raw: [Any] = ["a", "b"]
        #expect(AnthropicJSONValue(raw as NSArray) == .array([.string("a"), .string("b")]))
    }

    @Test func object_fromNSDictionary() {
        let raw: [String: Any] = ["key": "val"]
        #expect(AnthropicJSONValue(raw as NSDictionary) == .object(["key": .string("val")]))
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
