// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Capability to approve or deny pending tool calls on an agent session.
public protocol ToolApproving: Sendable {
    /// Approves a pending tool call.
    ///
    /// Call this after receiving a `.toolApprovalRequired` event.
    ///
    /// - Parameter callID: The pending tool call identifier to approve.
    func approve(callID: ToolCallID) async throws

    /// Denies a pending tool call.
    ///
    /// Call this after receiving a `.toolApprovalRequired` event.
    ///
    /// - Parameters:
    ///   - callID: The pending tool call identifier to deny.
    ///   - reason: The denial reason surfaced back through the tool failure path.
    func deny(callID: ToolCallID, reason: String) async throws
}
