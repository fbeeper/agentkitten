// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

/// Returns the current content of the scratchpad.
struct ReadScratchpadTool: AgentTool {
    struct Arguments: Codable, Sendable {}

    struct Output: Codable, Sendable {
        let content: String
    }

    static let name = "read_scratchpad"
    static let defaultDescription = "Returns the current content of the scratchpad file."

    let store: ScratchpadStore

    var schema: ToolSchema {
        ToolSchema(parameters: .object(properties: [:], required: []))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(content: await store.content)
    }
}
