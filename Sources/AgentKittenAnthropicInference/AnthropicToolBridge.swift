// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

/// Converts AgentKitten tool definitions into the Anthropic API wire format.
enum AnthropicToolBridge {
    /// Converts an ``AnyAgentTool`` to an ``AnthropicTool`` for the API request.
    static func anthropicTool(from tool: AnyAgentTool, rationaleDescription: String) -> AnthropicTool {
        AnthropicTool(
            name: tool.name,
            description: tool.description,
            inputSchema: injectingRationale(
                into: anthropicJSONValue(from: tool.schema.parameters),
                description: rationaleDescription,
            ),
        )
    }

    /// Recursively converts a ``JSONSchema`` node to ``AnthropicJSONValue``.
    static func anthropicJSONValue(from schema: JSONSchema) -> AnthropicJSONValue {
        switch schema {
        case .object(let properties, let required):
            var dict: [String: AnthropicJSONValue] = [
                "type": .string("object"),
                "properties": .object(properties.mapValues { anthropicJSONValue(from: $0) }),
            ]
            if !required.isEmpty {
                dict["required"] = .array(required.map { .string($0) })
            }
            return .object(dict)

        case .string(let description):
            return schemaNode(type: "string", description: description)

        case .integer(let description):
            return schemaNode(type: "integer", description: description)

        case .number(let description):
            return schemaNode(type: "number", description: description)

        case .boolean(let description):
            return schemaNode(type: "boolean", description: description)

        case .array(let items, let description):
            var dict: [String: AnthropicJSONValue] = [
                "type": .string("array"),
                "items": anthropicJSONValue(from: items),
            ]
            if let desc = description {
                dict["description"] = .string(desc)
            }
            return .object(dict)

        case .enumeration(let values, let description):
            var dict: [String: AnthropicJSONValue] = [
                "type": .string("string"),
                "enum": .array(values.map { .string($0) }),
            ]
            if let desc = description {
                dict["description"] = .string(desc)
            }
            return .object(dict)
        }
    }

    // MARK: - Private

    private static func injectingRationale(
        into schema: AnthropicJSONValue,
        description: String,
    ) -> AnthropicJSONValue {
        guard case .object(var dict) = schema,
              case .object(var props) = dict["properties"]
        else {
            return schema
        }
        props[ToolRationale.schemaKey] = schemaNode(type: "string", description: description)
        dict["properties"] = .object(props)
        if case .array(var req) = dict["required"] {
            req.append(.string(ToolRationale.schemaKey))
            dict["required"] = .array(req)
        } else {
            dict["required"] = .array([.string(ToolRationale.schemaKey)])
        }
        return .object(dict)
    }

    private static func schemaNode(type: String, description: String?) -> AnthropicJSONValue {
        var dict: [String: AnthropicJSONValue] = ["type": .string(type)]
        if let desc = description {
            dict["description"] = .string(desc)
        }
        return .object(dict)
    }
}
#endif
