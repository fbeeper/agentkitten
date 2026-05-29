// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

/// A violation of the ``InferenceEvent`` stream contract that every ``InferenceSession`` is expected to honor.
///
/// `InferenceDigester` enforces these same invariants at runtime via `precondition`/`throw`, so a malformed provider
/// stream crashes or aborts the agent loop in production. Surfacing them here as a typed, descriptive error lets
/// provider authors catch the bug in their own test suite instead.
public enum InferenceStreamContractViolation: Error, CustomStringConvertible, Equatable {
    /// The stream emitted an event after `.result`, which must be terminal.
    case eventAfterResult
    /// The stream finished without ever emitting `.result` (and without throwing).
    case missingResult
    /// The stream emitted `.result` while tool calls were still open.
    case openToolCallsAtResult(Set<ToolCallID>)
    /// A `.toolCallRequested` reused a `ToolCallID` that was already open
    /// (requested but not yet completed).
    case duplicateOpenToolCall(ToolCallID)
    /// A `.toolApprovalRequired` arrived without a preceding `.toolCallRequested`
    /// for the same `ToolCallID`.
    case approvalWithoutRequest(ToolCallID)
    /// A `.toolCallCompleted` arrived without a matching open `.toolCallRequested`.
    case completionWithoutRequest(ToolCallID)

    public var description: String {
        switch self {
        case .eventAfterResult:
            "Inference stream emitted an event after `.result`; `.result` must be the terminal event."
        case .missingResult:
            "Inference stream finished without emitting `.result` and without throwing."
        case .openToolCallsAtResult(let ids):
            "Inference stream emitted `.result` with open tool call id(s): \(ids.sorted().joined(separator: ", "))."
        case .duplicateOpenToolCall(let id):
            "Inference stream requested tool call id \"\(id)\" while a call with that id was still open."
        case .approvalWithoutRequest(let id):
            "Inference stream emitted `.toolApprovalRequired` for id \"\(id)\" with no preceding `.toolCallRequested`."
        case .completionWithoutRequest(let id):
            "Inference stream emitted `.toolCallCompleted` for id \"\(id)\" with no matching open `.toolCallRequested`."
        }
    }
}
