// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

@Suite("ToolRationale")
struct ToolRationaleTests {

    // MARK: - extracting(from:)

    @Test func extracting_returnsRationaleAndStripsKey() {
        let json = #"{"_agentKitten_toolRationale":"Get the current time","city":"Rome"}"#
        let (rationale, stripped) = ToolRationale.extracting(from: json)

        #expect(rationale == "Get the current time")
        #expect(!stripped.contains(ToolRationale.schemaKey))
        #expect(stripped.contains("Rome"))
    }

    @Test func extracting_returnsNilWhenKeyAbsent() {
        let (rationale, stripped) = ToolRationale.extracting(from: #"{"city":"Rome"}"#)

        #expect(rationale == nil)
        #expect(stripped.contains("Rome"))
    }

    @Test func extracting_returnsNilForEmptyString() {
        let json = #"{"_agentKitten_toolRationale":"","city":"Rome"}"#
        let (rationale, _) = ToolRationale.extracting(from: json)

        #expect(rationale == nil)
    }

    @Test func extracting_returnsNilWhenValueIsNotString() {
        let json = #"{"_agentKitten_toolRationale":42,"city":"Rome"}"#
        let (rationale, _) = ToolRationale.extracting(from: json)

        #expect(rationale == nil)
    }

    @Test func extracting_returnsFallbackOnMalformedJSON() {
        let bad = "not json at all"
        let (rationale, stripped) = ToolRationale.extracting(from: bad)

        #expect(rationale == nil)
        #expect(stripped == bad)
    }

    // MARK: - ToolSchema.usesReservedKey

    @Test func usesReservedKey_trueWhenKeyPresent() {
        let schema = ToolSchema(parameters: .object(
            properties: [ToolRationale.schemaKey: .string(description: nil)],
            required: []
        ))
        #expect(schema.usesReservedKey)
    }

    @Test func usesReservedKey_falseWhenKeyAbsent() {
        let schema = ToolSchema(parameters: .object(
            properties: ["city": .string(description: nil)],
            required: ["city"]
        ))
        #expect(!schema.usesReservedKey)
    }

    @Test func usesReservedKey_falseForNonObjectSchema() {
        let schema = ToolSchema(parameters: .string(description: nil))
        #expect(!schema.usesReservedKey)
    }

    // MARK: - PendingToolCall Codable

    @Test func pendingToolCall_roundTripsWithRationale() throws {
        let original = PendingToolCall(
            id: "call-1",
            name: "get_time",
            argumentsJSON: #"{"tz":"UTC"}"#,
            modelRationale: "Get the current time"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PendingToolCall.self, from: data)

        #expect(decoded == original)
    }

    @Test func pendingToolCall_decodesLegacyJSONWithoutRationale() throws {
        let legacy = #"{"id":"call-1","name":"get_time","argumentsJSON":"{\"tz\":\"UTC\"}"}"#
        let decoded = try JSONDecoder().decode(
            PendingToolCall.self,
            from: Data(legacy.utf8)
        )

        #expect(decoded.id == "call-1")
        #expect(decoded.modelRationale == nil)
    }
}
