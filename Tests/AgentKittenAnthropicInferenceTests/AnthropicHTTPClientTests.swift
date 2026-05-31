// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import AgentKittenInferenceSupport
import Testing

@Test func httpError_mapsContextWindowFailureToTypedInferenceError() {
    let error = AnthropicHTTPClient.error(
        statusCode: 400,
        body: """
        {"error":{
        "type":"invalid_request_error",
        "message":"prompt is too long: 200001 tokens > 200000 maximum"
        }}
        """,
    )

    guard case .contextWindowExceeded(let info) = error else {
        Issue.record("Expected contextWindowExceeded, got \(error)")
        return
    }
    #expect(info.provider == "Anthropic")
    #expect(info.message.contains("prompt is too long"))
}

@Test func httpError_doesNotInferContextWindowFailureFromMessageOnly() {
    let error = AnthropicHTTPClient.error(
        statusCode: 400,
        body: #"{"error":{"type":"api_error","message":"prompt is too long"}}"#,
    )

    guard case .invalidResponse(let message) = error else {
        Issue.record("Expected invalidResponse, got \(error)")
        return
    }
    #expect(message.contains("prompt is too long"))
}

@Test func httpError_doesNotInferContextWindowFailureFromGenericTokenMessage() {
    let error = AnthropicHTTPClient.error(
        statusCode: 400,
        body: """
        {"error":{
        "type":"invalid_request_error",
        "message":"token count exceeds supported maximum"
        }}
        """,
    )

    guard case .invalidResponse(let message) = error else {
        Issue.record("Expected invalidResponse, got \(error)")
        return
    }
    #expect(message.contains("token count exceeds"))
}

@Test func httpError_mapsAuthenticationFailureToTypedInferenceError() {
    let error = AnthropicHTTPClient.error(
        statusCode: 401,
        body: #"{"error":{"type":"authentication_error","message":"bad key"}}"#,
    )

    guard case .authenticationFailed(let info) = error else {
        Issue.record("Expected authenticationFailed, got \(error)")
        return
    }
    #expect(info.provider == "Anthropic")
    #expect(info.message.contains("bad key"))
    #expect(info.statusCode == 401)
}

@Test func httpError_keepsNonAuthenticationNonContextFailureAsInvalidResponse() {
    let error = AnthropicHTTPClient.error(
        statusCode: 500,
        body: #"{"error":{"type":"api_error","message":"server failed"}}"#,
    )

    guard case .invalidResponse(let message) = error else {
        Issue.record("Expected invalidResponse, got \(error)")
        return
    }
    #expect(message.contains("server failed"))
}
#endif
