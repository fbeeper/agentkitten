// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct TurnTraceSink {
    private let trace: AgentTrace
    private let approvalGate: ToolApprovalGate
    private let invocationID: InvocationID

    init(
        trace: AgentTrace,
        approvalGate: ToolApprovalGate,
        invocationID: InvocationID,
    ) {
        self.trace = trace
        self.approvalGate = approvalGate
        self.invocationID = invocationID
    }

    func record(
        kind: AgentTraceEntry.Kind,
    ) {
        trace.append(
            kind: kind,
            invocationID: invocationID,
        )
    }

    func record<Result: Sendable & Encodable>(
        _ event: ConversationEvent<Result>,
    ) async {
        switch event.kind {
        case .textDelta:
            break
        case .result(let result):
            await record(result: result)
        case .toolCallStarted(let name, let id, let argumentsJSON):
            record(
                kind: .message(.toolCall(ToolCallMessage(
                    id: id,
                    name: name,
                    argumentsJSON: argumentsJSON,
                ))),
            )
        case .toolApprovalRequired(let call):
            let context = await approvalGate.traceContext(callID: call.id)
            record(kind: .toolApprovalRequired(.init(call: call, context: context)))
        case .toolHookFired(let info):
            record(kind: .toolHookFired(info))
        case .toolCallCompleted(let name, let id, let outcome):
            let result = switch outcome {
            case .success(let content):
                ToolResultMessage(
                    callID: id,
                    name: name,
                    contentSummary: content.map(\.summary),
                    isError: false,
                )
            case .failure(let failure):
                ToolResultMessage(
                    callID: id,
                    name: name,
                    contentSummary: [.text(failure.resultJSON)],
                    isError: true,
                )
            }
            record(kind: .message(.toolResult(result)))
        }
    }

    private func record<Result: Sendable & Encodable>(
        result: Result,
    ) async {
        if let message = result as? AssistantMessage {
            record(kind: .message(.assistant(message)))
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let jsonData = try encoder.encode(result)
            guard let json = String(data: jsonData, encoding: .utf8) else {
                record(
                    kind: .error(.init(description: "Failed to decode structured result JSON as UTF-8")),
                )
                return
            }

            record(
                kind: .structuredResult(
                    type: String(describing: Result.self),
                    json: json,
                ),
            )
        } catch {
            record(kind: .error(.init(error)))
        }
    }
}
