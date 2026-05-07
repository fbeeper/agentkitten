// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import ArgumentParser
import Darwin
import Foundation
import AgentKitten
import AgentKittenCore

extension Playground {
    enum ToolPolicyOption: String, ExpressibleByArgument {
        case approve
        case ask
        case deny
    }
}

private struct PlaygroundAutoDenyPolicy: ToolExecutionPolicy {
    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .deny(reason: "Denied by Playground --tool-policy=deny")
    }
}

private struct PlaygroundInteractiveApprovalPolicy: ToolExecutionPolicy {
    func resolve(call: PendingToolCall, context: ToolExecutionContext) async -> ToolExecutionDecision {
        .requiresApproval
    }
}

actor PlaygroundToolApprovalMemory {
    private var alwaysApprovedToolNames: Set<String> = []

    func remembersAlwaysApproval(for toolName: String) -> Bool {
        alwaysApprovedToolNames.contains(toolName)
    }

    func rememberAlwaysApproval(for toolName: String) {
        alwaysApprovedToolNames.insert(toolName)
    }
}

enum PlaygroundToolApprovalPrompt {
    static let denialReason = "Denied in Playground"

    enum Resolution {
        case resolved
    }

    static func configuredPolicy(for option: Playground.ToolPolicyOption) -> AnyToolExecutionPolicy {
        switch option {
        case .approve:
            AnyToolExecutionPolicy(AutoApprovePolicy())
        case .ask:
            AnyToolExecutionPolicy(PlaygroundInteractiveApprovalPolicy())
        case .deny:
            AnyToolExecutionPolicy(PlaygroundAutoDenyPolicy())
        }
    }

    static func resolve(
        call: PendingToolCall,
        session: any ToolApproving,
        turn: Turn<AssistantMessage>,
        memory: PlaygroundToolApprovalMemory
    ) async throws -> Resolution {
        try await resolve(
            call: call,
            memory: memory,
            approve: {
                try await session.approve(callID: call.id)
            },
            deny: { reason in
                try await session.deny(callID: call.id, reason: reason)
            },
            onEOF: {
                await turn.cancel()
            }
        )
    }

    static func resolve(
        call: PendingToolCall,
        gate: ToolApprovalGate,
        memory: PlaygroundToolApprovalMemory
    ) async throws -> Resolution {
        try await resolve(
            call: call,
            memory: memory,
            approve: {
                try await gate.approve(callID: call.id)
            },
            deny: { reason in
                try await gate.deny(callID: call.id, reason: reason)
            },
            onEOF: {
                try? await gate.deny(callID: call.id, reason: denialReason)
            }
        )
    }

    private static func resolve(
        call: PendingToolCall,
        memory: PlaygroundToolApprovalMemory,
        approve: @escaping @Sendable () async throws -> Void,
        deny: @escaping @Sendable (String) async throws -> Void,
        onEOF: @escaping @Sendable () async -> Void
    ) async throws -> Resolution {
        if await memory.remembersAlwaysApproval(for: call.name) {
            try await approve()
            return .resolved
        }

        while true {
            print("\n\(PlaygroundToolEventFormatter.approvalRequired(call))")
            if let rationale = call.modelRationale {
                print("Rationale: \(rationale)")
            }
            print("Arguments: \(call.argumentsJSON)")
            print("Approve? [y]es / [a]lways / [n]o:", terminator: " ")
            fflush(stdout)

            guard let input = readLine() else {
                await onEOF()
                print()
                throw CancellationError()
            }

            switch parseDecision(input) {
            case .approve:
                try await approve()
                return .resolved
            case .alwaysApprove:
                await memory.rememberAlwaysApproval(for: call.name)
                try await approve()
                return .resolved
            case .deny:
                try await deny(denialReason)
                return .resolved
            case nil:
                print("Enter y, a, or n.")
            }
        }
    }

    private enum Decision {
        case approve
        case alwaysApprove
        case deny
    }

    private static func parseDecision(_ input: String) -> Decision? {
        switch input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "y", "yes", "approve":
            .approve
        case "a", "always":
            .alwaysApprove
        case "n", "no", "d", "deny":
            .deny
        default:
            nil
        }
    }
}
