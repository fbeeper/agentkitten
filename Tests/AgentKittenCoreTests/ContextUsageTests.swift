// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

@Suite("ContextUsage")
struct ContextUsageTests {
    // MARK: - fillPercent

    @Test("both unknown → nil")
    func fillPercentBothUnknown() {
        let usage = ContextUsage()
        #expect(usage.fillPercent == nil)
    }

    @Test("contextSize unknown → nil")
    func fillPercentSizeUnknown() {
        let usage = ContextUsage(contextTokens: 50, contextSize: .unknown)
        #expect(usage.fillPercent == nil)
    }

    @Test("contextTokens unknown → nil")
    func fillPercentTokensUnknown() {
        let usage = ContextUsage(contextTokens: .unknown, contextSize: 100)
        #expect(usage.fillPercent == nil)
    }

    @Test("contextSize zero → nil")
    func fillPercentSizeZero() {
        let usage = ContextUsage(contextTokens: 50, contextSize: 0)
        #expect(usage.fillPercent == nil)
    }

    @Test("80 of 100 → 0.8")
    func fillPercentHappyPath() throws {
        let usage = ContextUsage(contextTokens: 80, contextSize: 100)
        let fill = try #require(usage.fillPercent)
        #expect(fill == 0.8)
    }

    @Test("full context → 1.0")
    func fillPercentFull() throws {
        let usage = ContextUsage(contextTokens: 100, contextSize: 100)
        let fill = try #require(usage.fillPercent)
        #expect(fill == 1.0)
    }

    @Test("empty context → 0.0")
    func fillPercentEmpty() throws {
        let usage = ContextUsage(contextTokens: 0, contextSize: 100)
        let fill = try #require(usage.fillPercent)
        #expect(fill == 0.0)
    }

    // MARK: - Codable

    @Test("round-trips through JSON")
    func codableRoundTrip() throws {
        let original = ContextUsage(contextTokens: 42, contextSize: 128)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContextUsage.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("unknown fields encode as null")
    func unknownFieldsEncodeAsNull() throws {
        let usage = ContextUsage()
        let encoded = try JSONEncoder().encode(usage)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("\"contextTokens\":null"))
        #expect(json.contains("\"contextSize\":null"))
    }
}

// MARK: - AutomaticCompactionTrigger

@Suite("AutomaticCompactionTrigger")
struct AutomaticCompactionTriggerTests {
    @Test("percent ≤ 0 always triggers")
    func zeroPercentAlwaysTriggers() {
        let trigger = AutomaticCompactionTrigger.percentOfContextWindow(0)
        #expect(trigger.isMet(by: ContextUsage()))
        #expect(trigger.isMet(by: ContextUsage(contextTokens: 0, contextSize: 0)))
    }

    @Test("percent > 1 never triggers")
    func overOneNeverTriggers() {
        let trigger = AutomaticCompactionTrigger.percentOfContextWindow(1.1)
        #expect(!trigger.isMet(by: ContextUsage(contextTokens: 100, contextSize: 100)))
    }

    @Test("unknown usage does not trigger")
    func unknownUsageDoesNotTrigger() {
        let trigger = AutomaticCompactionTrigger.percentOfContextWindow(0.8)
        #expect(!trigger.isMet(by: ContextUsage()))
        #expect(!trigger.isMet(by: ContextUsage(contextTokens: .unknown, contextSize: 100)))
        #expect(!trigger.isMet(by: ContextUsage(contextTokens: 80, contextSize: .unknown)))
    }

    @Test("triggers at or above threshold")
    func triggersAtThreshold() {
        let trigger = AutomaticCompactionTrigger.percentOfContextWindow(0.8)
        #expect(trigger.isMet(by: ContextUsage(contextTokens: 80, contextSize: 100)))
        #expect(trigger.isMet(by: ContextUsage(contextTokens: 90, contextSize: 100)))
    }

    @Test("does not trigger below threshold")
    func doesNotTriggerBelowThreshold() {
        let trigger = AutomaticCompactionTrigger.percentOfContextWindow(0.8)
        #expect(!trigger.isMet(by: ContextUsage(contextTokens: 79, contextSize: 100)))
    }
}
