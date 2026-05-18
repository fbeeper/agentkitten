// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
@testable import AgentKittenInference
import Testing

@Test func anthropicSession_filtersRequestToolsByName() async throws {
    let client = CapturingStructuredHTTPClient(events: [
        .textDelta("Done."),
        .stopReason("end_turn"),
    ])
    let registry = ToolRegistry([
        AnyAgentTool(InferenceEchoTool()),
        AnyAgentTool(InferenceWeatherTool()),
    ])
    let session = makeAnthropicToolSelectionSession(registry: registry, client: client)

    for try await _ in try await session.run(
        UserMessage(text: "Hi"),
        parameters: InferenceRequestParameters(toolSelection: .including(["echo"])),
    ) {}

    let request = try #require(client.capturedRequest)
    #expect(request.tools?.map(\.name).sorted() == ["echo"])
}

@Test func anthropicSession_omitsRequestToolsWhenSelectionMatchesNone() async throws {
    let client = CapturingStructuredHTTPClient(events: [
        .textDelta("Done."),
        .stopReason("end_turn"),
    ])
    let registry = ToolRegistry([AnyAgentTool(InferenceEchoTool())])
    let session = makeAnthropicToolSelectionSession(registry: registry, client: client)

    for try await _ in try await session.run(
        UserMessage(text: "Hi"),
        parameters: InferenceRequestParameters(toolSelection: .including(["weather"])),
    ) {}

    let request = try #require(client.capturedRequest)
    #expect(request.tools == nil)
}

private func makeAnthropicToolSelectionSession(
    registry: ToolRegistry,
    client: some AnthropicHTTPStreaming,
) -> AnthropicInferenceSession {
    AnthropicInferenceSession(
        credentials: MockAPIKeyProvider("test-key"),
        defaultModel: "test-model",
        systemPrompt: nil,
        toolRuntime: testToolRuntime(registry: registry),
        clientFactory: { _ in client },
    )
}

struct InferenceWeatherTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let city: String
    }

    struct Output: Codable, Sendable {
        let forecast: String
    }

    static let name = "weather"
    static let description = "Returns a weather forecast."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: ["city": .string(description: "City name.")],
            required: ["city"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(forecast: "sunny in \(arguments.city)")
    }
}
