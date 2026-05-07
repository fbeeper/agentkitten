// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Executes tool calls dispatched by the model.
///
/// `ToolExecutor` is the single code path for registry lookup, argument decoding,
/// and tool invocation across all provider types.
public struct ToolExecutor: Sendable {
    /// The tool registry used for name-based dispatch.
    public let registry: ToolRegistry

    /// Creates an executor backed by the given registry.
    public init(registry: ToolRegistry) {
        self.registry = registry
    }

    /// Executes a pending tool call.
    ///
    /// - Throws: ``ToolExecutionError`` for not-found, invalid-argument-encoding,
    ///   and tool-thrown failures.
    /// - Returns: The provider-neutral result content on success.
    public func execute(_ call: PendingToolCall) async throws -> [ToolResultContent] {
        guard let agentTool = registry.lookup(name: call.name) else {
            throw ToolExecutionError.toolNotFound(name: call.name)
        }
        guard let argsData = call.argumentsJSON.data(using: .utf8) else {
            throw ToolExecutionError.invalidArgumentsEncoding
        }
        return try await agentTool.execute(argumentsJSON: argsData)
    }
}

// MARK: - ToolExecutionError

/// Errors that ``ToolExecutor`` can throw.
public enum ToolExecutionError: Error, Sendable {
    /// No tool with the given name is registered.
    case toolNotFound(name: String)
    /// The model's argument payload could not be encoded as UTF-8.
    case invalidArgumentsEncoding
}
