// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenAppleInference
import AgentKittenCore
import Foundation
import Testing

#if canImport(FoundationModels)
import FoundationModels

// MARK: - JSONSchemaBridge: propertyDescription

@Suite("JSONSchemaBridge propertyDescription")
struct JSONSchemaPropertyDescriptionTests {
    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func string_withDescription_returnsDescription() {
        #expect(JSONSchema.string(description: "A name.").propertyDescription == "A name.")
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func string_nilDescription_returnsNil() {
        #expect(JSONSchema.string(description: nil).propertyDescription == nil)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func integer_withDescription_returnsDescription() {
        #expect(JSONSchema.integer(description: "Count.").propertyDescription == "Count.")
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func number_nilDescription_returnsNil() {
        #expect(JSONSchema.number(description: nil).propertyDescription == nil)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func boolean_withDescription_returnsDescription() {
        #expect(JSONSchema.boolean(description: "Enabled?").propertyDescription == "Enabled?")
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func array_withDescription_returnsDescription() {
        let schema = JSONSchema.array(items: .string(description: nil), description: "A list.")
        #expect(schema.propertyDescription == "A list.")
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func array_nilDescription_returnsNil() {
        #expect(JSONSchema.array(items: .integer(description: nil), description: nil).propertyDescription == nil)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func object_returnsNil() {
        let schema = JSONSchema.object(properties: ["x": .string(description: nil)], required: ["x"])
        #expect(schema.propertyDescription == nil)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func enumeration_withDescription_appendsValues() {
        let desc = JSONSchema.enumeration(values: ["a", "b"], description: "Choose one.").propertyDescription
        #expect(desc?.hasPrefix("Choose one.") == true)
        #expect(desc?.contains("a, b") == true)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func enumeration_nilDescription_returnsValuesOnly() {
        let desc = JSONSchema.enumeration(values: ["x", "y"], description: nil).propertyDescription
        #expect(desc == "x, y")
    }
}

// MARK: - JSONSchemaBridge: toGenerationSchema

@Suite("JSONSchemaBridge toGenerationSchema")
struct JSONSchemaToGenerationSchemaTests {
    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func simpleObject_doesNotThrow() throws {
        let schema = ToolSchema(parameters: .object(
            properties: ["message": .string(description: "The message.")],
            required: ["message"],
        ))
        _ = try schema.toGenerationSchema(toolName: "echo", rationaleDescription: "Why you call this.")
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func primitiveProperties_doesNotThrow() throws {
        let schema = ToolSchema(parameters: .object(
            properties: [
                "query": .string(description: "Search query."),
                "limit": .integer(description: "Max results."),
                "enabled": .boolean(description: "Active?"),
                "score": .number(description: "Relevance."),
            ],
            required: ["query"],
        ))
        _ = try schema.toGenerationSchema(toolName: "search", rationaleDescription: "Perform search.")
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func arrayProperty_doesNotThrow() throws {
        let schema = ToolSchema(parameters: .object(
            properties: ["tags": .array(items: .string(description: nil), description: "Tag list.")],
            required: [],
        ))
        _ = try schema.toGenerationSchema(toolName: "tag", rationaleDescription: "Tag something.")
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func enumerationProperty_doesNotThrow() throws {
        let schema = ToolSchema(parameters: .object(
            properties: ["mode": .enumeration(values: ["fast", "slow"], description: "Speed mode.")],
            required: ["mode"],
        ))
        _ = try schema.toGenerationSchema(toolName: "run", rationaleDescription: "Run at speed.")
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func emptyObject_doesNotThrow() throws {
        let schema = ToolSchema(parameters: .object(properties: [:], required: []))
        _ = try schema.toGenerationSchema(toolName: "noop", rationaleDescription: "Does nothing.")
    }
}

// MARK: - AppleToolResultSupport

@Suite("AppleToolResultSupport")
struct AppleToolResultSupportTests {
    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func supports_textContent_returnsTrue() {
        #expect(AppleToolResultSupport.supports(.text("hello")))
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func supports_imageContent_returnsFalse() {
        #expect(!AppleToolResultSupport.supports(.image(mediaType: "image/png", data: Data([0x89]))))
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func unsupportedToolError_withTextOnlyRegistry_returnsNil() {
        let registry = ToolRegistry([AnyAgentTool(TextOnlyStubTool())])
        #expect(AppleToolResultSupport.unsupportedToolError(for: registry) == nil)
    }
}

// MARK: - TurnPreservationPlan

@Suite("TurnPreservationPlan for Apple transcript entries")
struct AppleTranscriptTurnPreservationPlanTests {
    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func emptyTranscript_bothArraysEmpty() {
        let entries = compactableEntries(from: Transcript(entries: []))
        let plan = TurnPreservationPlan(
            entries: entries,
            preservedRecentTurnCount: 1,
            isTurnStart: isTurnStarter,
        )
        #expect(plan.olderEntries(from: entries).isEmpty)
        #expect(plan.recentEntries(from: entries).isEmpty)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func zeroPreservedTurns_allEntriesSummarized() {
        let transcript = Transcript(entries: [
            makePrompt("q1"), makeResponse("a1"),
            makePrompt("q2"), makeResponse("a2"),
        ])
        let entries = compactableEntries(from: transcript)
        let plan = TurnPreservationPlan(
            entries: entries,
            preservedRecentTurnCount: 0,
            isTurnStart: isTurnStarter,
        )
        #expect(plan.olderEntries(from: entries).count == 4)
        #expect(plan.recentEntries(from: entries).isEmpty)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func instructionsFiltered_fromAllEntries() {
        let transcript = Transcript(entries: [
            makeInstructions("System."),
            makePrompt("q1"),
            makeResponse("a1"),
        ])
        let entries = compactableEntries(from: transcript)
        let plan = TurnPreservationPlan(
            entries: entries,
            preservedRecentTurnCount: 1,
            isTurnStart: isTurnStarter,
        )
        let allEntries = plan.olderEntries(from: entries) + plan.recentEntries(from: entries)
        let hasInstructions = allEntries.contains {
            if case .instructions = $0 { return true }
            return false
        }
        #expect(!hasInstructions)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func preservedCountExceedsActualTurns_allEntriesInRecent() {
        let transcript = Transcript(entries: [makePrompt("q1"), makeResponse("a1")])
        let entries = compactableEntries(from: transcript)
        let plan = TurnPreservationPlan(
            entries: entries,
            preservedRecentTurnCount: 99,
            isTurnStart: isTurnStarter,
        )
        #expect(plan.olderEntries(from: entries).isEmpty)
        #expect(plan.recentEntries(from: entries).count == 2)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func onePreservedTurn_splitsAtCorrectBoundary() {
        let transcript = Transcript(entries: [
            makePrompt("old-q"), makeResponse("old-a"),
            makePrompt("recent-q"), makeResponse("recent-a"),
        ])
        let entries = compactableEntries(from: transcript)
        let plan = TurnPreservationPlan(
            entries: entries,
            preservedRecentTurnCount: 1,
            isTurnStart: isTurnStarter,
        )
        #expect(plan.olderEntries(from: entries).count == 2)
        #expect(plan.recentEntries(from: entries).count == 2)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func twoPreservedTurns_splitsAtCorrectBoundary() {
        let transcript = Transcript(entries: [
            makePrompt("oldest-q"), makeResponse("oldest-a"),
            makePrompt("middle-q"), makeResponse("middle-a"),
            makePrompt("recent-q"), makeResponse("recent-a"),
        ])
        let entries = compactableEntries(from: transcript)
        let plan = TurnPreservationPlan(
            entries: entries,
            preservedRecentTurnCount: 2,
            isTurnStart: isTurnStarter,
        )
        #expect(plan.olderEntries(from: entries).count == 2)
        #expect(plan.recentEntries(from: entries).count == 4)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    private func compactableEntries(from transcript: Transcript) -> [Transcript.Entry] {
        Array(transcript).filter {
            if case .instructions = $0 { false } else { true }
        }
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    private func isTurnStarter(_ entry: Transcript.Entry) -> Bool {
        if case .prompt = entry { return true }
        return false
    }
}

// MARK: - AppleInferenceProvider sessionCompatibility

@Suite("AppleInferenceProvider sessionCompatibility")
struct AppleSessionCompatibilityTests {
    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func identicalConfigs_reuse() {
        let cfg = makeConfig()
        #expect(AppleInferenceProvider().sessionCompatibility(from: cfg, to: cfg) == .reuse)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func toolSelectionChange_rebuildsSession() {
        let result = AppleInferenceProvider().sessionCompatibility(
            from: makeConfig(toolSelection: .all),
            to: makeConfig(toolSelection: .disabled),
        )
        #expect(result == .rebuildSession)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func modelKeyChange_rebuildsSession() {
        let result = AppleInferenceProvider().sessionCompatibility(
            from: makeConfig(modelKey: .default),
            to: makeConfig(modelKey: .contentTagging),
        )
        #expect(result == .rebuildSession)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func modelKeyNilToValue_rebuildsSession() {
        let result = AppleInferenceProvider().sessionCompatibility(
            from: makeConfig(modelKey: nil),
            to: makeConfig(modelKey: .contentTagging),
        )
        #expect(result == .rebuildSession)
    }

    @available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
    @Test func providerChange_replaces() {
        let result = AppleInferenceProvider().sessionCompatibility(
            from: makeConfig(providerRef: .default),
            to: makeConfig(providerRef: .ofType(AppleInferenceProvider.self)),
        )
        #expect(result == .replace)
    }
}

// MARK: - Helpers

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func makeConfig(
    toolSelection: ToolSelection = .all,
    providerRef: ProviderReference = .default,
    modelKey: AppleLanguageModel? = nil,
) -> EffectiveExecutionConfiguration {
    var context = InferenceContext.empty
    context[AppleLanguageModelKey.self] = modelKey
    return EffectiveExecutionConfiguration(
        toolSelection: toolSelection,
        provider: providerRef,
        inferenceContext: context,
    )
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func makePrompt(_ text: String) -> FoundationModels.Transcript.Entry {
    .prompt(FoundationModels.Transcript.Prompt(segments: [
        .text(FoundationModels.Transcript.TextSegment(content: text)),
    ]))
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func makeResponse(_ text: String) -> FoundationModels.Transcript.Entry {
    .response(FoundationModels.Transcript.Response(assetIDs: [], segments: [
        .text(FoundationModels.Transcript.TextSegment(content: text)),
    ]))
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func makeInstructions(_ text: String) -> FoundationModels.Transcript.Entry {
    .instructions(FoundationModels.Transcript.Instructions(segments: [
        .text(FoundationModels.Transcript.TextSegment(content: text)),
    ], toolDefinitions: []))
}

private struct TextOnlyStubTool: AgentTool {
    struct Arguments: Codable, Sendable {}
    struct Output: Codable, Sendable {}

    static let name = "stub"
    static let defaultDescription = "A text-only stub."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(properties: [:], required: []))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output()
    }
}

#endif
