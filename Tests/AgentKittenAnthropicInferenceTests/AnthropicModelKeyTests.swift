// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import AgentKittenInferenceSupport
import Testing

/// AnthropicModelKey in inferenceContext overrides the provider default model.
@Test func session_anthropicModelKey_overridesDefaultModel() async throws {
    let client = CapturingStructuredHTTPClient(events: [
        .textDelta("ok"),
        .stopReason("end_turn"),
    ])
    let session = AnthropicInferenceSession(
        client: client,
        defaultModel: "default-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
    )

    var inferenceContext = InferenceContext()
    inferenceContext[AnthropicModelKey.self] = "override-model"
    let parameters = InferenceRequestParameters(inferenceContext: inferenceContext)
    for try await _ in try await session.run(UserMessage(text: "hi"), parameters: parameters) {}

    let request = try #require(client.capturedRequest)
    #expect(request.model == "override-model")
}

/// When AnthropicModelKey is absent, buildRequest falls back to defaultModel.
@Test func session_anthropicModelKey_fallsBackToDefaultWhenAbsent() async throws {
    let client = CapturingStructuredHTTPClient(events: [
        .textDelta("ok"),
        .stopReason("end_turn"),
    ])
    let session = AnthropicInferenceSession(
        client: client,
        defaultModel: "default-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(),
    )

    let parameters = InferenceRequestParameters()
    for try await _ in try await session.run(UserMessage(text: "hi"), parameters: parameters) {}

    let request = try #require(client.capturedRequest)
    #expect(request.model == "default-model")
}
#endif
