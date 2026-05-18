// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A validated, name-keyed store of tools available to an agent.
///
/// `ToolRegistry` enforces unique tool names at creation time, preventing silent
/// overwriting of duplicate registrations. It is the single source of truth for
/// tool lookup and description during a conversation.
///
/// ## Future extensibility
/// The registry is backed by a dictionary (O(1) name lookup). When tool sets grow
/// large enough to exceed context-window limits, the lookup strategy can be swapped
/// for semantic retrieval (e.g. a vector database) without changing call sites.
public struct ToolRegistry: Sendable {
    private let tools: [String: AnyAgentTool]

    /// Creates a registry from the given tools.
    ///
    /// - Precondition: All tool names must be unique.
    ///   Duplicate names are a programming error and trigger a `preconditionFailure`.
    public init(_ tools: [AnyAgentTool] = []) {
        var dict: [String: AnyAgentTool] = [:]
        for agentTool in tools {
            precondition(
                dict[agentTool.name] == nil,
                "Duplicate tool name '\(agentTool.name)' — each tool must have a unique name.",
            )
            dict[agentTool.name] = agentTool
        }
        self.tools = dict
    }

    /// All registered tools, suitable for sending to the model as descriptions.
    ///
    /// The model reads these descriptions to decide which tool to call. After
    /// the model returns a tool name, use ``lookup(name:)`` to dispatch.
    public var all: [AnyAgentTool] { Array(tools.values) }

    /// Returns registered tools allowed by `selection`.
    public func tools(matching selection: ToolSelection) -> [AnyAgentTool] {
        all.filter { selection.allows(toolName: $0.name) }
    }

    /// Returns a registry containing only tools allowed by `selection`.
    public func filtered(by selection: ToolSelection) -> ToolRegistry {
        ToolRegistry(tools(matching: selection))
    }

    /// Returns the tool registered under `name`, or `nil` if not found.
    ///
    /// Used at dispatch time after the model has selected a tool by name.
    public func lookup(name: String) -> AnyAgentTool? { tools[name] }

    /// Returns a new registry with additional tools appended.
    ///
    /// - Parameter tools: Additional tools to register.
    /// - Precondition: Additional tool names must not collide with existing or
    ///   newly added tools.
    /// - Returns: A new registry containing the existing and additional tools.
    public func adding(_ tools: [AnyAgentTool]) -> ToolRegistry {
        for agentTool in tools {
            precondition(
                self.tools[agentTool.name] == nil,
                "Duplicate tool name '\(agentTool.name)' — each tool must have a unique name.",
            )
        }
        return ToolRegistry(all + tools)
    }
}
