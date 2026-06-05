// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Public approval gate shared by `AgentSession` and direct provider sessions.
///
/// Callers create one gate, pass it into ``ToolRuntime``, observe
/// ``InferenceEvent/toolApprovalRequired(call:)`` or
/// ``AgentEvent/Kind/toolApprovalRequired(call:)``, and resolve the pending
/// call on this gate.
public actor ToolApprovalGate {
    private struct PendingState {
        var approval: PendingApproval
        let traceContext: CustomContextSnapshot?

        func updating(approval: PendingApproval) -> Self {
            Self(
                approval: approval,
                traceContext: traceContext,
            )
        }
    }

    private enum PendingApproval {
        case pending
        case waiting(CheckedContinuation<ToolApprovalDecision, Never>)
        case resolved(ToolApprovalDecision)
    }

    private var pending: [ToolCallID: PendingState]

    /// Creates a gate that tracks pending approvals until the caller resolves them.
    public init() {
        pending = [:]
    }

    /// Marks the tool call as pending before the approval-required event is emitted.
    public func register(
        callID: ToolCallID,
        traceContext: CustomContextSnapshot? = nil,
    ) throws {
        guard pending[callID] == nil else {
            throw ToolApprovalResolutionError.duplicatePendingApproval(callID: callID)
        }
        pending[callID] = PendingState(
            approval: .pending,
            traceContext: traceContext,
        )
    }

    /// Suspends until the caller approves, denies, or cancels the pending tool call.
    public func waitForResolution(callID: ToolCallID) async throws -> ToolApprovalDecision {
        guard let current = pending[callID] else {
            throw ToolApprovalResolutionError.noPendingApproval(callID: callID)
        }
        switch current.approval {
        case .pending:
            return await withCheckedContinuation { continuation in
                pending[callID] = current.updating(approval: .waiting(continuation))
            }
        case .waiting:
            throw ToolApprovalResolutionError.duplicatePendingWait(callID: callID)
        case .resolved(let resolution):
            pending.removeValue(forKey: callID)
            return resolution
        }
    }

    /// Approves a pending tool call.
    public func approve(callID: ToolCallID) throws {
        try resolve(callID: callID, as: .approved)
    }

    /// Denies a pending tool call.
    public func deny(callID: ToolCallID, reason: String) throws {
        try resolve(callID: callID, as: .denied(reason: reason))
    }

    /// Cancels a pending tool call if one exists.
    public func cancel(callID: ToolCallID) {
        guard let current = pending[callID] else {
            return
        }
        switch current.approval {
        case .pending:
            pending[callID] = current.updating(
                approval: .resolved(.denied(reason: ToolApprovalDecision.cancelledReason)),
            )
        case .waiting(let continuation):
            pending.removeValue(forKey: callID)
            continuation.resume(
                returning: .denied(reason: ToolApprovalDecision.cancelledReason),
            )
        case .resolved:
            return
        }
    }

    func traceContext(callID: ToolCallID) -> CustomContextSnapshot? {
        pending[callID]?.traceContext
    }

    private func resolve(
        callID: ToolCallID,
        as resolution: ToolApprovalDecision,
    ) throws {
        guard let current = pending[callID] else {
            throw ToolApprovalResolutionError.noPendingApproval(callID: callID)
        }
        switch current.approval {
        case .pending:
            pending[callID] = current.updating(approval: .resolved(resolution))
        case .waiting(let continuation):
            pending.removeValue(forKey: callID)
            continuation.resume(returning: resolution)
        case .resolved:
            pending[callID] = current.updating(approval: .resolved(resolution))
        }
    }
}

/// The result of waiting on a ``ToolApprovalGate`` request.
public enum ToolApprovalDecision: Sendable, Equatable {
    /// The pending tool call was approved and may execute.
    case approved
    /// The pending tool call was denied or cancelled.
    case denied(reason: String)

    static let cancelledReason = "cancelled"
}
