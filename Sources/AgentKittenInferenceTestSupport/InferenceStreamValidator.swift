// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

/// Pure, provider-agnostic checker for the ``InferenceEvent`` stream ordering contract.
///
/// Run the provider *raw* stream through ``validate(_:)`` (before `InferenceDigester` and any other logic),
/// To assert the invariants a session must satisfy:
/// 1. `.toolApprovalRequired` is preceded by a matching-id `.toolCallRequested`.
/// 2. `.toolCallCompleted` is preceded by a matching-id `.toolCallRequested`.
/// 3. The stream terminates with `.result` or throws — never finishes silently.
/// 4. No events are emitted after `.result`.
/// 5. `.result` is not emitted while any tool call is still open.
/// 6. Parallel tool calls each map to a distinct open `.toolCallRequested`.
public enum InferenceStreamValidator {
    /// Consumes `stream`, asserting the ``InferenceEvent`` stream contract, and
    /// returns the collected events.
    ///
    /// - A thrown error from `stream` itself is a valid terminal condition and is
    ///   re-thrown unchanged; the caller decides whether an error was expected.
    /// - A contract violation is thrown as ``InferenceStreamContractViolation``.
    ///
    /// - Parameter stream: The raw inference event stream to validate.
    /// - Returns: Every event observed, in order, ending with `.result`.
    /// - Throws: ``InferenceStreamContractViolation`` on a contract breach, or any
    ///   error the underlying stream throws.
    @discardableResult
    public static func validate<Output: Sendable, S: AsyncSequence & Sendable>(
        _ stream: S,
    ) async throws -> [InferenceEvent<Output>] where S.Element == InferenceEvent<Output> {
        var events: [InferenceEvent<Output>] = []
        var openCalls: Set<ToolCallID> = []
        var sawResult = false

        for try await event in stream {
            if sawResult {
                throw InferenceStreamContractViolation.eventAfterResult
            }
            if case .result = event {
                guard openCalls.isEmpty else {
                    throw InferenceStreamContractViolation.openToolCallsAtResult(openCalls)
                }
                sawResult = true
            } else {
                try checkToolOrdering(event, openCalls: &openCalls)
            }
            events.append(event)
        }

        guard sawResult else {
            throw InferenceStreamContractViolation.missingResult
        }
        return events
    }

    /// Validates the tool-call ordering invariants for a single non-`.result`
    /// event, updating the set of currently-open tool calls.
    private static func checkToolOrdering<Output: Sendable>(
        _ event: InferenceEvent<Output>,
        openCalls: inout Set<ToolCallID>,
    ) throws {
        switch event {
        case .delta, .toolHookFired, .result:
            break

        case .toolCallRequested(let id, _, _):
            guard openCalls.insert(id).inserted else {
                throw InferenceStreamContractViolation.duplicateOpenToolCall(id)
            }

        case .toolApprovalRequired(let call):
            guard openCalls.contains(call.id) else {
                throw InferenceStreamContractViolation.approvalWithoutRequest(call.id)
            }

        case .toolCallCompleted(let id, _, _):
            guard openCalls.remove(id) != nil else {
                throw InferenceStreamContractViolation.completionWithoutRequest(id)
            }
        }
    }
}
