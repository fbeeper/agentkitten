// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenCore
@testable import AgentKittenOpenAIInference
import Foundation
import Testing

@Suite("OpenAI context-window resolution")
struct OpenAIContextWindowTests {
    @Test("OpenAIContextWindowKey overrides discovery and skips the metadata request")
    func contextWindowKeyOverridesDiscovery() async throws {
        // Discovery would report a different size; the override must win and discovery must not run.
        let client = MockOpenAIHTTPClient(
            responses: [[.usage(50), .stopReason("stop")]],
            maxInputTokensByModel: ["test-model": 9999],
        )
        let session = makeOpenAITestSession(client: client)

        var inferenceContext = InferenceContext()
        inferenceContext[OpenAIContextWindowKey.self] = 8000
        let parameters = InferenceRequestParameters(inferenceContext: inferenceContext)
        for try await _ in try await session.run(UserMessage(text: "hi"), parameters: parameters) {}

        let usage = try await session.contextUsage()
        #expect(usage.contextSize == .tokens(8000))
        #expect(usage.contextTokens == .tokens(50))
        // Override short-circuits resolution before any /models lookup.
        #expect(client.capturedModelInfoRequests.isEmpty)
    }

    @Test("falls back to endpoint discovery when no override is set")
    func usesDiscoveryWhenNoOverride() async throws {
        let client = MockOpenAIHTTPClient(
            responses: [[.usage(50), .stopReason("stop")]],
            maxInputTokensByModel: ["test-model": 4096],
        )
        let session = makeOpenAITestSession(client: client)

        let parameters = InferenceRequestParameters()
        for try await _ in try await session.run(UserMessage(text: "hi"), parameters: parameters) {}

        let usage = try await session.contextUsage()
        #expect(usage.contextSize == .tokens(4096))
        #expect(client.capturedModelInfoRequests == ["test-model"])
    }
}

@Suite("OpenAIModelInfoResponse decoding")
struct OpenAIModelInfoResponseTests {
    @Test("resolves max_context_length when no other window field is present")
    func fallsBackToMaxContextLength() throws {
        let json = Data(#"{"max_context_length":262144}"#.utf8)
        let info = try JSONDecoder().decode(OpenAIModelInfoResponse.self, from: json)
        #expect(info.resolvedMaxInputTokens == 262_144)
    }

    @Test("resolves to nil when no window field is present")
    func resolvesToNilWhenAbsent() throws {
        let json = Data(#"{"id":"qwen","object":"model","owned_by":"organization_owner"}"#.utf8)
        let info = try JSONDecoder().decode(OpenAIModelInfoResponse.self, from: json)
        #expect(info.resolvedMaxInputTokens == nil)
    }
}
#endif
