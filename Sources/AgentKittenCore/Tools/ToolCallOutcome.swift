// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The outcome of a tool invocation, carried by
/// ``AgentEvent/Kind/toolCallCompleted(name:id:outcome:)``.
public enum ToolCallOutcome: Sendable, Equatable {
    /// The tool executed successfully and returned provider-neutral content.
    case success(content: [ToolResultContent])
    /// The tool could not be executed.
    case failure(ToolCallFailure)
}

/// Describes why a tool invocation failed.
public enum ToolCallFailure: Sendable, Equatable, Codable {
    /// The tool's implementation threw an error, or the executor could not
    /// dispatch the call (e.g. tool not found, invalid argument encoding).
    case execution(message: String)
    /// The per-turn tool-step budget was exhausted before this call could run.
    case stepLimitExceeded
    /// The tool call was denied by the configured tool execution policy.
    case denied(reason: String)

    /// A clean JSON representation stored in trace summaries as text content.
    ///
    /// This is what the client app observes in failed ``ToolResultMessage/contentSummary``
    /// entries today.
    public var resultJSON: String {
        switch self {
        case .execution(let message):
            return Self.errorJSON(message)
        case .stepLimitExceeded:
            return Self.errorJSON(AgentKittenLocalization.string("tools.stepLimitExceededError"))
        case .denied(let reason):
            return Self.errorJSON(reason)
        }
    }

    private static func errorJSON(_ message: String) -> String {
        let payload = ["error": message]
        if let data = try? JSONEncoder().encode(payload),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        // Fallback: JSONEncoder failed (should not happen for [String:String]),
        // but preserve the message by escaping it manually rather than discarding it.
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"error\":\"\(escaped)\"}"
    }
}
