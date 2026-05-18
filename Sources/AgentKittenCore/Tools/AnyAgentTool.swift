// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - ToolCallID

/// An opaque identifier for a single tool invocation.
public typealias ToolCallID = String

// MARK: - AnyAgentTool

/// A type-erased wrapper around an ``AgentTool`` conformance.
///
/// Accepts raw JSON `Data` for arguments and returns provider-neutral content blocks.
/// Create instances with ``init(_:)``.
public struct AnyAgentTool: Sendable {
    /// The tool's unique routing name.
    public let name: String
    /// Human-readable description forwarded to the model.
    public let description: String
    /// The JSON schema describing the tool's input parameters.
    public let schema: ToolSchema
    /// Advisory capability declaration.
    public let capabilities: ToolCapabilities

    private let executeHandler: @Sendable (Data) async throws -> [ToolResultContent]

    /// Creates a type-erased wrapper from a concrete ``AgentTool``.
    public init<T: AgentTool>(_ agentTool: T) {
        precondition(
            !agentTool.schema.usesReservedKey,
            "Tool '\(T.name)' defines parameter '\(ToolRationale.schemaKey)', which is reserved by AgentKitten.",
        )
        name = T.name
        description = T.description
        schema = agentTool.schema
        capabilities = agentTool.capabilities
        executeHandler = { data in
            let args = try JSONDecoder().decode(T.Arguments.self, from: data)
            let output = try await agentTool.execute(arguments: args)
            let encoded = try JSONEncoder().encode(output)
            let text = String(data: encoded, encoding: .utf8) ?? "{}"
            return [.text(text)]
        }
    }

    /// Creates a type-erased wrapper from a concrete ``RichAgentTool``.
    public init<T: RichAgentTool>(_ agentTool: T) {
        precondition(
            !agentTool.schema.usesReservedKey,
            "Tool '\(T.name)' defines parameter '\(ToolRationale.schemaKey)', which is reserved by AgentKitten.",
        )
        name = T.name
        description = T.description
        schema = agentTool.schema
        capabilities = agentTool.capabilities
        executeHandler = { data in
            let args = try JSONDecoder().decode(T.Arguments.self, from: data)
            return try await agentTool.execute(arguments: args)
        }
    }

    /// Executes the tool with raw JSON argument data and returns provider-neutral content blocks.
    public func execute(argumentsJSON: Data) async throws -> [ToolResultContent] {
        try await executeHandler(argumentsJSON)
    }
}
