// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
import AgentKittenInferenceSupport

/// Converts AgentKitten tool definitions into the Anthropic API wire format.
enum AnthropicToolBridge {
    /// Converts an ``AnyAgentTool`` to an ``AnthropicTool`` for the API request.
    static func anthropicTool(from tool: AnyAgentTool, rationaleDescription: String) -> AnthropicTool {
        AnthropicTool(
            name: tool.name,
            description: tool.description,
            inputSchema: InferenceProviderJSONValue.injectingRationale(
                into: InferenceProviderJSONValue.encoding(tool.schema.parameters),
                description: rationaleDescription,
            ),
        )
    }
}
#endif
