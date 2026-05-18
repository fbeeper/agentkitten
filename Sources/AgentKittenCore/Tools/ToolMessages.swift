// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Utilities for the model-rationale field injected into every tool schema.
public enum ToolRationale {
    /// Key injected into tool schemas and extracted from model responses.
    public static let schemaKey = "_agentKitten_toolRationale"
    /// Description forwarded to the model as the schema property description.
    public static var schemaDescription: String {
        AgentKittenLocalization.string("tools.rationaleSchemaDescription")
    }

    /// Extracts the rationale and returns the JSON with the schema key removed.
    /// Returns `nil` rationale when absent, malformed, empty, or not a string.
    /// Returns the original string unchanged when parsing fails.
    public static func extracting(from argumentsJSON: String) -> (rationale: String?, strippedJSON: String) {
        guard
            let data = argumentsJSON.data(using: .utf8),
            var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (nil, argumentsJSON)
        }
        let rationale = obj.removeValue(forKey: schemaKey) as? String
        let stripped: String
        if let strippedData = try? JSONSerialization.data(withJSONObject: obj),
           let strippedString = String(data: strippedData, encoding: .utf8) {
            stripped = strippedString
        } else {
            stripped = argumentsJSON
        }
        return (rationale?.isEmpty == false ? rationale : nil, stripped)
    }
}

/// A record of a tool call requested by the model.
public struct ToolCallMessage: Sendable, Codable, Equatable, Hashable {
    /// Unique identifier for this invocation.
    public let id: ToolCallID
    /// The tool's name.
    public let name: String
    /// The model's argument payload as a JSON string.
    public let argumentsJSON: String

    /// Creates a tool call message.
    public init(id: ToolCallID, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// A record of a tool's result returned after execution.
public struct ToolResultMessage: Sendable, Codable, Equatable, Hashable {
    /// The ID of the originating tool call.
    public let callID: ToolCallID
    /// The tool's name.
    public let name: String
    /// A lossy summary of the tool result payload.
    public let contentSummary: [ToolResultContentSummary]
    /// Whether the tool execution produced an error.
    public let isError: Bool

    /// Creates a tool result message.
    public init(
        callID: ToolCallID,
        name: String,
        contentSummary: [ToolResultContentSummary],
        isError: Bool = false,
    ) {
        self.callID = callID
        self.name = name
        self.contentSummary = contentSummary
        self.isError = isError
    }
}

/// A pending tool invocation used as a transport struct for tool dispatch.
public struct PendingToolCall: Sendable, Codable, Equatable, Hashable {
    /// Unique identifier for this invocation.
    public let id: ToolCallID
    /// The tool's name.
    public let name: String
    /// The model's argument payload as a JSON string.
    public let argumentsJSON: String
    /// The model's self-reported rationale for requesting this call.
    /// UX context only — may be nil, inaccurate, or adversarially supplied.
    public let modelRationale: String?

    /// Creates a pending tool call record.
    public init(id: ToolCallID, name: String, argumentsJSON: String, modelRationale: String? = nil) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.modelRationale = modelRationale
    }
}
