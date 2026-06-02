// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport

/// Converts AgentKitten tool definitions into the OpenAI API wire format.
enum OpenAIToolBridge {
    /// Converts an ``AnyAgentTool`` to an ``OpenAITool`` for the API request.
    static func openAITool(from tool: AnyAgentTool, rationaleDescription: String) -> OpenAITool {
        OpenAITool(
            type: "function",
            function: OpenAITool.FunctionDefinition(
                name: tool.name,
                description: tool.description,
                parameters: InferenceProviderJSONValue.injectingRationale(
                    into: InferenceProviderJSONValue.encoding(tool.schema.parameters),
                    description: rationaleDescription,
                ),
            ),
        )
    }
}
#endif
