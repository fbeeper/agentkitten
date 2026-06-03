// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
@testable import AgentKittenAnthropicInference
@testable import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation
import Testing

// MARK: - AnthropicToolBridge injection

@Suite("AnthropicToolBridge rationale injection")
struct AnthropicToolBridgeRationaleTests {
    private let tool = AnyAgentTool(InferenceEchoTool())

    @Test func anthropicTool_injectsRationaleInProperties() {
        let converted = AnthropicToolBridge.anthropicTool(
            from: tool,
            rationaleDescription: ToolRationale.schemaDescription,
        )

        guard case .object(let dict) = converted.inputSchema,
              case .object(let props) = dict["properties"]
        else {
            Issue.record("inputSchema is not an object with properties")
            return
        }
        #expect(props[ToolRationale.schemaKey] != nil)
    }

    @Test func anthropicTool_addsRationaleToRequired() {
        let converted = AnthropicToolBridge.anthropicTool(
            from: tool,
            rationaleDescription: ToolRationale.schemaDescription,
        )

        guard case .object(let dict) = converted.inputSchema,
              case .array(let req) = dict["required"]
        else {
            Issue.record("inputSchema missing required array")
            return
        }
        #expect(req.contains(.string(ToolRationale.schemaKey)))
    }

    @Test func anthropicTool_usesCustomRationaleDescription() {
        let custom = "Custom rationale description"
        let converted = AnthropicToolBridge.anthropicTool(
            from: tool,
            rationaleDescription: custom,
        )

        guard case .object(let dict) = converted.inputSchema,
              case .object(let props) = dict["properties"],
              case .object(let rationaleNode) = props[ToolRationale.schemaKey],
              case .string(let desc) = rationaleNode["description"]
        else {
            Issue.record("Could not read rationale property description")
            return
        }
        #expect(desc == custom)
    }

    @Test func anthropicTool_preservesExistingRequiredFields() {
        let converted = AnthropicToolBridge.anthropicTool(
            from: tool,
            rationaleDescription: ToolRationale.schemaDescription,
        )

        guard case .object(let dict) = converted.inputSchema,
              case .array(let req) = dict["required"]
        else {
            Issue.record("inputSchema missing required array")
            return
        }
        #expect(req.contains(.string("message")))
        #expect(req.contains(.string(ToolRationale.schemaKey)))
    }
}

// MARK: - Session integration: modelRationale populated from SSE tool call

@Suite("AnthropicInferenceSession rationale extraction")
struct AnthropicSessionRationaleTests {
    private func makeSession(
        toolRuntime: ToolRuntime,
        client: some AnthropicHTTPStreaming,
    ) -> AnthropicInferenceSession {
        AnthropicInferenceSession(
            client: client,
            defaultModel: "test-model",
            systemPrompt: nil,
            toolRuntime: toolRuntime,
        )
    }

    @Test func session_populatesModelRationaleOnApprovalEvent() async throws {
        let argsJSON = #"{"_agentKitten_toolRationale":"Echo the greeting","message":"hello"}"#
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "echo", argsJSON: argsJSON), .stopReason("tool_use")],
            [.textDelta("Done"), .stopReason("end_turn")],
        ])
        let runtime = testToolRuntime(
            registry: ToolRegistry([AnyAgentTool(InferenceEchoTool())]),
            executionPolicy: RequiresApprovalPolicy(),
        )
        let session = makeSession(toolRuntime: runtime, client: mock)

        var capturedCall: PendingToolCall?
        for try await event in try await session.run(
            UserMessage(text: "Hi"),
            parameters: InferenceRequestParameters(),
        ) {
            if case .toolApprovalRequired(let call) = event {
                capturedCall = call
                try await runtime.approvalGate.approve(callID: call.id)
            }
        }

        let call = try #require(capturedCall)
        #expect(call.modelRationale == "Echo the greeting")
        #expect(!call.argumentsJSON.contains(ToolRationale.schemaKey))
    }

    @Test func session_stripsRationaleFromToolCallRequestedEvent() async throws {
        let argsJSON = #"{"_agentKitten_toolRationale":"Echo the greeting","message":"hello"}"#
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "echo", argsJSON: argsJSON), .stopReason("tool_use")],
            [.textDelta("Done"), .stopReason("end_turn")],
        ])
        let session = makeSession(
            toolRuntime: testToolRuntime(registry: ToolRegistry([AnyAgentTool(InferenceEchoTool())])),
            client: mock,
        )

        var requestedArgsJSON: String?
        for try await event in try await session.run(
            UserMessage(text: "Hi"),
            parameters: InferenceRequestParameters(),
        ) {
            if case .toolCallRequested(_, _, let args) = event {
                requestedArgsJSON = args
            }
        }

        let args = try #require(requestedArgsJSON)
        #expect(!args.contains(ToolRationale.schemaKey))
        #expect(args.contains("hello"))
    }

    @Test func session_setsNilRationaleWhenKeyAbsent() async throws {
        let mock = MockHTTPClient(responses: [
            [.toolCallReady(id: "call-1", name: "echo", argsJSON: #"{"message":"hello"}"#), .stopReason("tool_use")],
            [.textDelta("Done"), .stopReason("end_turn")],
        ])
        let runtime = testToolRuntime(
            registry: ToolRegistry([AnyAgentTool(InferenceEchoTool())]),
            executionPolicy: RequiresApprovalPolicy(),
        )
        let session = makeSession(toolRuntime: runtime, client: mock)

        var capturedCall: PendingToolCall?
        for try await event in try await session.run(
            UserMessage(text: "Hi"),
            parameters: InferenceRequestParameters(),
        ) {
            if case .toolApprovalRequired(let call) = event {
                capturedCall = call
                try await runtime.approvalGate.approve(callID: call.id)
            }
        }

        #expect(try #require(capturedCall).modelRationale == nil)
    }
}

// MARK: - ToolRuntime rationaleSchemaDescription

@Suite("ToolRuntime rationaleSchemaDescription")
struct ToolRuntimeRationaleTests {
    @Test func toolRuntime_defaultsToToolRationaleSchemaDescription() {
        let toolBehavior = ToolBehavior()
        let runtime = ToolRuntime(toolDefinition: .noTools, toolBehavior: toolBehavior)
        #expect(runtime.rationaleSchemaDescription == ToolRationale.schemaDescription)
    }

    @Test func toolBehavior_customRationaleGuidance_propagatesSchemaDescription() {
        let custom = "My custom rationale"
        let toolBehavior = ToolBehavior(rationaleSchemaDescription: custom)
        #expect(toolBehavior.rationaleSchemaDescription == custom)
    }
}

// MARK: - Private helpers

private struct RequiresApprovalPolicy: ToolExecutionPolicy {
    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .requiresApproval
    }
}
#endif
