// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// Future: AppIntent / AssistantIntent bridge — tools must be concrete named types, not closures.
// Future: @Tool macro synthesizes name, description, schema from Arguments struct.

/// A typed tool that an agent can invoke during inference.
///
/// Conform concrete structs to `AgentTool` to expose callable functions to the model.
/// Closure-based tool factories are intentionally excluded from the public API — all tools
/// must be concrete named types to support the future `@Tool` / `AssistantIntent` bridge.
///
/// ## Defining a tool
/// ```swift
/// struct GetWeatherTool: AgentTool {
///     struct Arguments: Codable, Sendable {
///         let location: String
///     }
///     struct Output: Codable, Sendable {
///         let temperature: Double
///         let condition: String
///     }
///     static let name = "get_weather"
///     static let description = "Returns current weather for a location."
///     var schema: ToolSchema { ToolSchema(parameters: .object(
///         properties: ["location": .string(description: "City and state, e.g. 'Austin, TX'")],
///         required: ["location"]
///     ))}
///     func execute(arguments: Arguments) async throws -> Output { ... }
/// }
///
/// // Wrap for use with Agent:
/// let tools: [AnyAgentTool] = [AnyAgentTool(GetWeatherTool())]
/// ```
public protocol AgentTool: Sendable {
    /// The typed argument payload the model provides when invoking this tool.
    associatedtype Arguments: Codable & Sendable
    /// The typed result the tool returns after execution.
    associatedtype Output: Codable & Sendable

    /// The tool's unique routing name. Must be stable across runs.
    ///
    /// Static because `AssistantIntent` metadata is compile-time.
    static var name: String { get }

    /// A short description that the model uses to decide when to invoke the tool.
    ///
    /// Static because `AssistantIntent` metadata is compile-time.
    static var description: String { get }

    /// The JSON schema for this tool's input parameters.
    var schema: ToolSchema { get }

    /// Advisory declaration of OS capabilities this tool may access.
    ///
    /// Defaults to ``ToolCapabilities/none``.
    var capabilities: ToolCapabilities { get }

    /// Executes the tool with the given typed arguments and returns its output.
    func execute(arguments: Arguments) async throws -> Output
}

extension AgentTool {
    public var capabilities: ToolCapabilities {
        .none
    }
}

/// A typed tool that returns provider-neutral rich content blocks.
public protocol RichAgentTool: Sendable {
    /// The typed argument payload the model provides when invoking this tool.
    associatedtype Arguments: Codable & Sendable

    /// The tool's unique routing name. Must be stable across runs.
    static var name: String { get }

    /// A short description that the model uses to decide when to invoke the tool.
    static var description: String { get }

    /// The JSON schema for this tool's input parameters.
    var schema: ToolSchema { get }

    /// Advisory declaration of OS capabilities this tool may access.
    ///
    /// Defaults to ``ToolCapabilities/none``.
    var capabilities: ToolCapabilities { get }

    /// Executes the tool with the given typed arguments and returns rich output blocks.
    func execute(arguments: Arguments) async throws -> [ToolResultContent]
}

extension RichAgentTool {
    public var capabilities: ToolCapabilities {
        .none
    }
}
