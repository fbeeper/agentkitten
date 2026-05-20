// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import AgentKittenInferenceSupport
import Testing

@Test func httpError_mapsContextWindowFailureToTypedInferenceError() {
    let error = AnthropicHTTPClient.error(
        statusCode: 400,
        body: #"{"error":{"type":"invalid_request_error","message":"prompt is too long"}}"#,
    )

    guard case .contextWindowExceeded(let info) = error else {
        Issue.record("Expected contextWindowExceeded, got \(error)")
        return
    }
    #expect(info.provider == "Anthropic")
    #expect(info.message.contains("prompt is too long"))
}

@Test func httpError_keepsNonContextFailureAsInvalidResponse() {
    let error = AnthropicHTTPClient.error(
        statusCode: 401,
        body: #"{"error":{"type":"authentication_error","message":"bad key"}}"#,
    )

    guard case .invalidResponse(let message) = error else {
        Issue.record("Expected invalidResponse, got \(error)")
        return
    }
    #expect(message.contains("bad key"))
}
