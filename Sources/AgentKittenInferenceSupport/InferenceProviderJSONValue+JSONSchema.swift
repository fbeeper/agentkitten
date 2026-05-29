// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

extension InferenceProviderJSONValue {
    /// Converts a ``JSONSchema`` node to a ``InferenceProviderJSONValue`` that serializes as standard JSON Schema.
    package static func encoding(_ schema: JSONSchema) -> InferenceProviderJSONValue {
        switch schema {
        case .object(let properties, let required):
            var dict: [String: InferenceProviderJSONValue] = [
                "type": .string("object"),
                "properties": .object(properties.mapValues { encoding($0) }),
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
            var dict: [String: InferenceProviderJSONValue] = [
                "type": .string("array"),
                "items": encoding(items),
            ]
            if let desc = description {
                dict["description"] = .string(desc)
            }
            return .object(dict)

        case .enumeration(let values, let description):
            var dict: [String: InferenceProviderJSONValue] = [
                "type": .string("string"),
                "enum": .array(values.map { .string($0) }),
            ]
            if let desc = description {
                dict["description"] = .string(desc)
            }
            return .object(dict)
        }
    }

    /// Injects an AgentKitten rationale field into a tool parameter schema ``InferenceProviderJSONValue``.
    ///
    /// The rationale key is appended to `properties` and added to the `required` array so
    /// the model is prompted to explain its reasoning before invoking the tool.
    package static func injectingRationale(
        into schema: InferenceProviderJSONValue,
        description: String,
    ) -> InferenceProviderJSONValue {
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

    private static func schemaNode(type: String, description: String?) -> InferenceProviderJSONValue {
        var dict: [String: InferenceProviderJSONValue] = ["type": .string(type)]
        if let desc = description {
            dict["description"] = .string(desc)
        }
        return .object(dict)
    }
}
