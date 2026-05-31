// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenCore
import AgentKittenInferenceTestSupport
@testable import AgentKittenOpenAIInference
import Testing

/// Smoke-checks that the OpenAI text session emits streams satisfying the shared
/// ``InferenceEvent`` contract, alongside the provider-specific tests. Drives a
/// real session over a mock HTTP client and pipes its raw stream through
/// ``InferenceStreamValidator``.
@Suite("OpenAI stream conformance")
struct OpenAIStreamConformanceTests {
    @Test("Text turn satisfies the inference stream contract")
    func textTurnConforms() async throws {
        let client = MockOpenAIHTTPClient(responses: [
            [.textDelta("Hello there"), .stopReason("stop"), .usage(12)],
        ])
        let session = makeOpenAITestSession(client: client)
        let stream = try await session.run(
            UserMessage(text: "Hi"),
            parameters: InferenceRequestParameters(toolSelection: .disabled),
        )
        let events = try await InferenceStreamValidator.validate(stream)
        guard case .result = events.last else {
            Issue.record("Expected the stream to terminate with `.result`.")
            return
        }
    }
}
#endif
