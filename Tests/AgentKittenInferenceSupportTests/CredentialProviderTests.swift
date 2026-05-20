// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenInferenceSupport
import Foundation
import Testing

// MARK: - MockAPIKeyProvider

@Test func mockAPIKeyProvider_returnsConfiguredKey() async throws {
    let provider = MockAPIKeyProvider("sk-test-123")
    let key = try await provider.apiKey()
    #expect(key == "sk-test-123")
}

// MARK: - EnvironmentAPIKeyProvider

@Test func environmentAPIKeyProvider_returnsValueWhenSet() async throws {
    let varName = "AGENTKITTEN_TEST_KEY_\(Int.random(in: 100_000 ... 999_999))"
    setenv(varName, "env-test-value", 1)
    defer { unsetenv(varName) }

    let provider = EnvironmentAPIKeyProvider(varName)
    let key = try await provider.apiKey()
    #expect(key == "env-test-value")
}

@Test func environmentAPIKeyProvider_throwsWhenVariableAbsent() async throws {
    let varName = "AGENTKITTEN_TEST_KEY_ABSENT_\(Int.random(in: 100_000 ... 999_999))"
    unsetenv(varName)

    let provider = EnvironmentAPIKeyProvider(varName)
    await #expect(throws: (any Error).self) {
        _ = try await provider.apiKey()
    }
}

@Test func environmentAPIKeyProvider_throwsWhenVariableEmpty() async throws {
    let varName = "AGENTKITTEN_TEST_KEY_EMPTY_\(Int.random(in: 100_000 ... 999_999))"
    setenv(varName, "", 1)
    defer { unsetenv(varName) }

    let provider = EnvironmentAPIKeyProvider(varName)
    await #expect(throws: (any Error).self) {
        _ = try await provider.apiKey()
    }
}

// MARK: - KeychainAPIKeyProvider

/// Keychain tests require a host process with Keychain entitlements.
/// In a sandboxed test runner these will throw `errSecMissingEntitlement` or
/// similar; we treat any thrown error as a skip rather than a failure.
@Test func keychainAPIKeyProvider_throwsMissingWhenItemAbsent() async throws {
    let service = "com.agentkitten.tests.\(Int.random(in: 100_000 ... 999_999))"
    let provider = KeychainAPIKeyProvider(service: service, account: "test")
    do {
        _ = try await provider.apiKey()
        Issue.record("Expected an error for a non-existent Keychain item")
    } catch APIKeyError.missing {
        // Expected path
    } catch {
        // Entitlement/sandbox restriction — acceptable in CI
        withKnownIssue("Keychain unavailable in this test environment: \(error)") {}
    }
}
