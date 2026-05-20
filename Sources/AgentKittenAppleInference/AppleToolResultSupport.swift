// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
import Foundation

enum AppleToolResultSupport {
    static let supportedKinds: Set<ToolResultContentKind> = [.text]

    static func unsupportedToolError(for registry: ToolRegistry) -> InferenceError? {
        let unsupportedToolNames = registry.all
            .filter { !$0.capabilities.producesOnly(supportedKinds) }
            .map(\.name)
            .sorted()
        guard !unsupportedToolNames.isEmpty else {
            return nil
        }
        let names = unsupportedToolNames.joined(separator: ", ")
        return .unsupportedConfiguration(
            "Apple provider supports text-only tool results. Unsupported tools: \(names)",
        )
    }

    static func supports(_ content: ToolResultContent) -> Bool {
        supportedKinds.contains(content.kind)
    }
}

#endif
