// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

/// Overwrites the scratchpad with the provided content.
struct WriteScratchpadTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let content: String
    }

    struct Output: Codable, Sendable {
        let written: Bool
        let message: String
    }

    static let name = "write_scratchpad"
    static let description = "Overwrites the scratchpad file with the provided content."

    let store: ScratchpadStore

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "content": .string(description: "The new complete content for the scratchpad."),
            ],
            required: ["content"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        await store.write(arguments.content)
        return Output(written: true, message: "Scratchpad updated successfully.")
    }
}
