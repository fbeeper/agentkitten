// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// The JSON schema for a tool's input parameters.
public struct ToolSchema: Sendable, Codable {
    /// An object schema whose properties describe the tool's parameters.
    public let parameters: JSONSchema

    /// Creates a schema wrapping the given parameter object schema.
    public init(parameters: JSONSchema) {
        self.parameters = parameters
    }

    /// `true` when the top-level object schema defines a property whose name
    /// collides with AgentKitten's reserved rationale key.
    var usesReservedKey: Bool {
        guard case .object(let properties, _) = parameters else {
            return false
        }
        return properties.keys.contains(ToolRationale.schemaKey)
    }
}
