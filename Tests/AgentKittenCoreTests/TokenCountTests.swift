// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

@Suite("TokenCount")
struct TokenCountTests {
    // MARK: - init(_ value: Int?)

    @Test("nil maps to .unknown")
    func initNilIsUnknown() {
        #expect(TokenCount(nil) == .unknown)
    }

    @Test("negative maps to .unknown")
    func initNegativeIsUnknown() {
        let negative: Int = -1
        #expect(TokenCount(negative) == .unknown)
    }

    @Test("zero maps to .tokens(0)")
    func initZeroIsTokens() {
        #expect(TokenCount(0) == .tokens(0))
    }

    @Test("positive maps to .tokens")
    func initPositiveIsTokens() {
        #expect(TokenCount(42) == .tokens(42))
    }

    // MARK: - value

    @Test(".unknown has nil value")
    func unknownValueIsNil() {
        #expect(TokenCount.unknown.value == nil)
    }

    @Test(".tokens has non-nil value")
    func tokensValueIsUnwrapped() {
        #expect(TokenCount.tokens(7).value == 7)
    }

    // MARK: - ExpressibleByIntegerLiteral

    @Test("integer literal produces .tokens")
    func integerLiteralProducesTokens() {
        let count: TokenCount = 100
        #expect(count == .tokens(100))
    }

    // MARK: - Comparable

    @Test(".unknown sorts below any .tokens")
    func unknownLessThanTokens() {
        #expect(TokenCount.unknown < TokenCount.tokens(0))
        #expect(TokenCount.unknown < TokenCount.tokens(1_000_000))
    }

    @Test(".unknown is not greater than .tokens")
    func unknownNotGreaterThanTokens() {
        #expect(!(TokenCount.unknown > TokenCount.tokens(0)))
    }

    @Test(".tokens compare by value")
    func tokensSortsByValue() {
        #expect(TokenCount.tokens(5) < TokenCount.tokens(10))
        #expect(TokenCount.tokens(10) > TokenCount.tokens(5))
        #expect(TokenCount.tokens(10) == TokenCount.tokens(10))
    }

    @Test(".unknown does not sort below itself")
    func unknownNotLessThanUnknown() {
        #expect(!(TokenCount.unknown < TokenCount.unknown))
    }

    // MARK: - * operator

    @Test(".unknown * fraction stays .unknown")
    func unknownScaledIsUnknown() {
        #expect(TokenCount.unknown * 0.8 == .unknown)
    }

    @Test(".tokens scaled by fraction")
    func tokensScaledByFraction() {
        #expect(TokenCount.tokens(100) * 0.8 == .tokens(80))
    }

    @Test(".tokens * 0 is .tokens(0)")
    func tokensScaledByZero() {
        #expect(TokenCount.tokens(100) * 0.0 == .tokens(0))
    }

    // MARK: - CustomStringConvertible

    @Test(".unknown description is 'unknown'")
    func unknownDescription() {
        #expect(TokenCount.unknown.description == "unknown")
    }

    @Test(".tokens description is the count")
    func tokensDescription() {
        #expect(TokenCount.tokens(42).description == "42")
    }

    // MARK: - Codable

    @Test(".unknown round-trips through JSON as null")
    func unknownCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(TokenCount.unknown)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(json == "null")
        let decoded = try JSONDecoder().decode(TokenCount.self, from: encoded)
        #expect(decoded == .unknown)
    }

    @Test(".tokens round-trips through JSON as integer")
    func tokensCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(TokenCount.tokens(99))
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(json == "99")
        let decoded = try JSONDecoder().decode(TokenCount.self, from: encoded)
        #expect(decoded == .tokens(99))
    }
}
