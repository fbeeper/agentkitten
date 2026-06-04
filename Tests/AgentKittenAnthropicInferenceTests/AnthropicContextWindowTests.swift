// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import AgentKittenInferenceSupport
import Testing

/// AnthropicContextWindowKey overrides endpoint discovery and short-circuits the lookup.
@Test func session_anthropicContextWindowKey_overridesDiscovery() async throws {
    let client = CountingModelInfoHTTPClient()
    let session = AnthropicInferenceSession(
        client: client,
        defaultModel: "default-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
    )

    var inferenceContext = InferenceContext()
    inferenceContext[AnthropicContextWindowKey.self] = 200_000
    let parameters = InferenceRequestParameters(inferenceContext: inferenceContext)
    for try await _ in try await session.run(UserMessage(text: "hi"), parameters: parameters) {}

    let usage = try await session.contextUsage()
    #expect(usage.contextSize == .tokens(200_000))
    // The override wins before any /models lookup is attempted.
    #expect(client.callCount == 0)
}

/// When the key is absent, the session falls back to endpoint discovery.
@Test func session_anthropicContextWindow_usesDiscoveryWhenNoOverride() async throws {
    let client = ModelInfoHTTPClient(maxInputTokensValue: 1_048_576)
    let session = AnthropicInferenceSession(
        client: client,
        defaultModel: "default-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
    )

    let parameters = InferenceRequestParameters()
    for try await _ in try await session.run(UserMessage(text: "hi"), parameters: parameters) {}

    let usage = try await session.contextUsage()
    #expect(usage.contextSize == .tokens(1_048_576))
}
#endif
