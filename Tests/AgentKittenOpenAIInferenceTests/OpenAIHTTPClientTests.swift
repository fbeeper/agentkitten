// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenCore
@testable import AgentKittenOpenAIInference
import Testing

@Test func openAIHTTPError_mapsContextWindowFailureToTypedInferenceError() {
    let error = OpenAIHTTPClient.error(
        statusCode: 400,
        body: """
        {"error":{
        "message":"This model's maximum context length is 128000 tokens.",
        "type":"invalid_request_error",
        "code":"context_length_exceeded"
        }}
        """,
    )

    guard case .contextWindowExceeded(let info) = error else {
        Issue.record("Expected contextWindowExceeded, got \(error)")
        return
    }
    #expect(info.provider == "OpenAI")
    #expect(info.message.contains("maximum context length"))
}

@Test func openAIHTTPError_mapsAuthenticationFailureToTypedInferenceError() {
    let error = OpenAIHTTPClient.error(
        statusCode: 401,
        body: """
        {"error":{
        "message":"Incorrect API key provided.",
        "type":"invalid_request_error",
        "code":"invalid_api_key"
        }}
        """,
    )

    guard case .authenticationFailed(let info) = error else {
        Issue.record("Expected authenticationFailed, got \(error)")
        return
    }
    #expect(info.provider == "OpenAI")
    #expect(info.message == "OpenAI API returned HTTP 401: authentication failed (error code: invalid_api_key)")
    #expect(info.statusCode == 401)
}

@Test func openAIHTTPError_mapsAuthorizationFailureToTypedInferenceError() {
    let error = OpenAIHTTPClient.error(
        statusCode: 403,
        body: """
        {"error":{
        "message":"Project does not have access to this model.",
        "type":"invalid_request_error",
        "code":"model_not_found"
        }}
        """,
    )

    guard case .authenticationFailed(let info) = error else {
        Issue.record("Expected authenticationFailed, got \(error)")
        return
    }
    #expect(info.provider == "OpenAI")
    #expect(info.message == "OpenAI API returned HTTP 403: authentication failed (error code: model_not_found)")
    #expect(info.statusCode == 403)
}

@Test func openAIHTTPError_keepsNonAuthenticationNonContextFailureAsInvalidResponse() {
    let error = OpenAIHTTPClient.error(
        statusCode: 500,
        body: #"{"error":{"message":"server failed","type":"server_error"}}"#,
    )

    guard case .invalidResponse(let message) = error else {
        Issue.record("Expected invalidResponse, got \(error)")
        return
    }
    #expect(message.contains("server failed"))
}

@Test func openAIHTTPError_doesNotInferContextWindowFailureFromMessageOnly() {
    let error = OpenAIHTTPClient.error(
        statusCode: 400,
        body: """
        {"error":{
        "message":"This model's maximum context length is 128000 tokens.",
        "type":"invalid_request_error"
        }}
        """,
    )

    guard case .invalidResponse(let message) = error else {
        Issue.record("Expected invalidResponse, got \(error)")
        return
    }
    #expect(message.contains("maximum context length"))
}
#endif
