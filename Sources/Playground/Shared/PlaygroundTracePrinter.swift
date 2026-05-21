// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import Foundation

enum PlaygroundTracePrinter {
    static func printTurnTrace(
        trace: AgentTrace,
        invocationID: InvocationID,
    ) async {
        let entries = await trace.snapshot().filter { $0.invocationID == invocationID }
        guard !entries.isEmpty else {
            return
        }

        print("\n--- AgentTrace \(invocationID) ---")
        for (index, entry) in entries.enumerated() {
            print(format(entry, number: index + 1))
        }
        print("--- End AgentTrace ---")
    }

    static func trim(_ text: String, limit: Int = 96) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard singleLine.count > limit else {
            return singleLine
        }
        let endIndex = singleLine.index(singleLine.startIndex, offsetBy: limit)
        return "\(singleLine[..<endIndex])..."
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func format(
        _ entry: AgentTraceEntry,
        number: Int,
    ) -> String {
        let prefix = String(format: "%02d", number)
        switch entry.kind {
        case .turnStarted(let userMessage):
            return "\(prefix). turnStarted    user \"\(trim(userMessage.text))\""
        case .message(let message):
            return "\(prefix). message        \(describe(message))"
        case .structuredResult(let type, let json):
            return "\(prefix). structured     \(trim(type, limit: 40)) \(trim(json, limit: 56))"
        case .executionPreparation(let info):
            return "\(prefix). preparation    \(info.verdict.rawValue) \(describePreparation(info))"
        case .conversationResolved(let info):
            return """
            \(prefix). resolved       conv=\(info.identity.conversationID) \
            inference=\(info.identity.inferenceSessionID) \(info.resolutionKind.rawValue)
            """
        case .contextCompaction(let info):
            return """
            \(prefix). compaction     \(info.mode.rawValue) \
            \(describeCompaction(info))
            """
        case .stateMutation(let mutation):
            return "\(prefix). state          \(describe(mutation))"
        case .toolApprovalRequired(let info):
            return "\(prefix). approval       \(describeApproval(info))"
        case .toolHookFired(let info):
            let transformed = info.transformed ? " [transformed]" : ""
            return "\(prefix). hookFired       \(info.hookName) \(info.phase) \(info.toolName)\(transformed)"
        case .validation(let validation):
            let validator = trim(validation.validator, limit: 24)
            let message = trim(validation.message)
            return """
            \(prefix). validation     \(validator) \(validation.result.rawValue) \
            "\(message)"
            """
        case .error(let error):
            return "\(prefix). error          \(trim(error.description))"
        case .turnCompleted(let outcome):
            return "\(prefix). completed      \(describe(outcome))"
        }
    }

    private static func describePreparation(
        _ info: AgentTraceEntry.Kind.ExecutionPreparationInfo,
    ) -> String {
        var parts: [String] = [
            "provider=\(describeProvider(info.provider))",
            "toolSelection=\(describeSelection(info.toolSelection))",
            "toolStepBudget=\(describeBudget(info.toolStepBudget))",
            "temperature=\(info.inferenceConfiguration.temperature)",
        ]
        if let inferenceContext = info.inferenceContext {
            parts.append("inferenceContext=\(describe(inferenceContext))")
        }
        if let overrides = info.turnOverrides {
            parts.append("overrides=\(describeOverrides(overrides))")
        }
        return parts.joined(separator: " ")
    }

    private static func describeProvider(_ provider: ProviderReferenceSnapshot) -> String {
        switch provider {
        case .default:
            "default"
        case .named(let name):
            name
        }
    }

    private static func describeSelection(
        _ selection: ToolSelectionSnapshot,
    ) -> String {
        switch selection {
        case .all:
            "all"
        case .disabled:
            "disabled"
        case .including(let names):
            "including(\(names.joined(separator: ",")))"
        case .excluding(let names):
            "excluding(\(names.joined(separator: ",")))"
        }
    }

    private static func describeBudget(
        _ budget: ToolStepBudgetSnapshot,
    ) -> String {
        switch budget {
        case .disabled:
            "disabled"
        case .budget(let count):
            "budget(\(count))"
        case .unbounded:
            "unbounded"
        }
    }

    private static func describeOverrides(
        _ overrides: TurnOverridesSnapshot,
    ) -> String {
        var parts: [String] = []
        if let sel = overrides.toolSelection {
            parts.append("toolSelection=\(describeSelection(sel))")
        }
        if let budget = overrides.toolStepBudget {
            parts.append("toolStepBudget=\(describeBudget(budget))")
        }
        if let config = overrides.inferenceConfiguration {
            parts.append("temperature=\(config.temperature)")
        }
        if let provider = overrides.provider {
            parts.append("provider=\(describeProvider(provider))")
        }
        return parts.joined(separator: ",")
    }

    private static func describe(_ message: AgentMessage) -> String {
        switch message {
        case .assistant(let assistant):
            "assistant \"\(trim(assistant.text))\""
        case .user(let user):
            "user \"\(trim(user.text))\""
        case .system(let system):
            "system \"\(trim(system.text))\""
        case .toolCall(let call):
            "toolCall(name: \(call.name), id: \(call.id))"
        case .toolResult(let result):
            "toolResult(name: \(result.name), id: \(result.callID), isError: \(result.isError))"
        }
    }

    private static func describe(_ outcome: AgentTraceEntry.Kind.TurnOutcome) -> String {
        switch outcome {
        case .completed:
            "completed"
        case .cancelled:
            "cancelled"
        case .failed(let error):
            "failed(\(error.description))"
        }
    }

    private static func describe(_ mutation: AgentTraceEntry.Kind.StateMutation) -> String {
        switch mutation.operation {
        case .set:
            let valueType = mutation.valueType ?? "unknown"
            return "set key=\(mutation.key) type=\(valueType)"
        case .remove:
            return "remove key=\(mutation.key)"
        }
    }

    private static func describe(_ result: ContextCompactionResult) -> String {
        switch result {
        case .compacted(let compacted):
            """
            compacted tokens=\(compacted.usageBefore.contextTokens)->\(compacted.usageAfter.contextTokens)
            """
        case .skipped(let reason):
            "skipped reason=\(describe(reason))"
        }
    }

    private static func describe(_ reason: ContextCompactionResult.SkipReason) -> String {
        switch reason {
        case .disabled:
            "disabled"
        case .sessionReleased:
            "sessionReleased"
        case .noActiveConversation:
            "noActiveConversation"
        case .conversationReplaced:
            "conversationReplaced"
        case .triggerNotMet(let usage):
            "triggerNotMet(tokens=\(usage.contextTokens))"
        case .inferenceError(let error):
            "inferenceError(\(error))"
        case .failed(let message):
            "failed(\(message))"
        }
    }

    private static func describeCompaction(
        _ info: AgentTraceEntry.Kind.ContextCompactionInfo,
    ) -> String {
        var parts: [String] = []
        if let provider = info.provider {
            parts.append("provider=\(describeProvider(provider))")
        }
        if let configuration = info.inferenceConfiguration {
            parts.append("temperature=\(configuration.temperature)")
            parts.append("maxTokens=\(configuration.maxTokens)")
        }
        if let inferenceContext = info.inferenceContext {
            parts.append("context=\(describe(inferenceContext))")
        }
        parts.append(describe(info.result))
        return parts.joined(separator: " ")
    }

    private static func describe(_ snapshot: CustomContextSnapshot) -> String {
        let entries = snapshot.entries.map { "\($0.key)=\($0.valueSummary)" }
        return "[\(entries.joined(separator: ","))]"
    }

    private static func describeApproval(
        _ info: AgentTraceEntry.Kind.ToolApprovalRequiredInfo,
    ) -> String {
        var parts = ["tool \(info.call.name) (\(info.call.id))"]
        if let context = info.context {
            parts.append("context=\(describe(context))")
        }
        return parts.joined(separator: " ")
    }
}
