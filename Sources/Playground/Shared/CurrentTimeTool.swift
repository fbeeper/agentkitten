// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import Foundation

/// Returns the current date and time in ISO 8601 and human-readable formats.
struct CurrentTimeTool: AgentTool {
    struct Arguments: Codable, Sendable {}
    struct Output: Codable, Sendable {
        let iso8601: String
        let readable: String
    }

    static let name = "current_time"
    static let defaultDescription = "Returns the current date and time."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(properties: [:], required: []))
    }

    func execute(arguments: Arguments) async throws -> Output {
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now)
        let readable = DateFormatter.localizedString(from: now, dateStyle: .long, timeStyle: .medium)
        return Output(iso8601: iso, readable: readable)
    }
}
