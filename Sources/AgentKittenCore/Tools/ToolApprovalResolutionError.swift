// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Errors produced when resolving a pending tool approval.
public enum ToolApprovalResolutionError: Error, Sendable, Equatable {
    /// No unresolved approval request exists for the provided tool call ID.
    case noPendingApproval(callID: ToolCallID)
    /// An approval request for the provided tool call ID is already pending.
    case duplicatePendingApproval(callID: ToolCallID)
    /// More than one waiter attempted to suspend on the same pending tool call.
    case duplicatePendingWait(callID: ToolCallID)
}
