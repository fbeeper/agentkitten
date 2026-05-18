// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Declares what OS capabilities a tool may access.
///
/// Advisory only in V1 — documents intent and enables UI disclosure.
/// Future: drives pre-flight validation and XPC isolation profiles.
public struct ToolCapabilities: Sendable {
    /// Path prefixes the tool may read or write.
    public var filesystemPaths: [String]
    /// Whether the tool requires network access.
    public var network: Bool
    /// The kinds of content this tool may emit in its result.
    public var toolResultContentKinds: Set<ToolResultContentKind>

    /// Creates a capability declaration.
    public init(
        filesystemPaths: [String] = [],
        network: Bool = false,
        toolResultContentKinds: Set<ToolResultContentKind> = [.text],
    ) {
        self.filesystemPaths = filesystemPaths
        self.network = network
        self.toolResultContentKinds = toolResultContentKinds
    }

    /// No capabilities declared.
    public static let none = ToolCapabilities()
}

extension ToolCapabilities {
    /// Returns whether every emitted tool-result kind is supported by the caller.
    public func producesOnly(_ supportedKinds: Set<ToolResultContentKind>) -> Bool {
        toolResultContentKinds.isSubset(of: supportedKinds)
    }
}
