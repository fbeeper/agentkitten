// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import AgentKittenCore
import ArgumentParser

extension Playground {
    /// Single-turn inference that exercises the provider/session layer directly.
    ///
    /// Demonstrates the lower-level API: provider → session → stream.
    struct Generate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Single-turn inference via the provider/session layer.",
        )

        @Option(name: .long, help: "The prompt to send to the inference provider.")
        var prompt: String

        @Option(name: .long, help: "System prompt for the session.")
        var system: String?

        @Option(name: .long, help: "Inference provider: mock, apple, anthropic.")
        var provider: ProviderOption = .apple

        @Option(name: .long, help: "Tool execution policy: approve, ask, or deny.")
        var toolPolicy: ToolPolicyOption = .approve

        func run() async throws {
            print("AgentKitten Playground v\(AgentKitten.version)")
            print("Prompt: \(prompt)")
            print("Response: ", terminator: "")
            flushStdout()

            let runtime = PlaygroundSessionFactory.makeToolRuntime(
                policy: PlaygroundToolApprovalPrompt.configuredPolicy(for: toolPolicy),
            )
            let session = try PlaygroundSessionFactory.makeSession(
                for: provider,
                systemPrompt: system,
                runtime: runtime,
            )
            try await stream(session: session, gate: runtime.approvalGate)
        }

        private func stream<S: InferenceSession>(
            session: S,
            gate: ToolApprovalGate,
        ) async throws {
            let memory = PlaygroundToolApprovalMemory()
            let events = try await session.run(UserMessage(text: prompt), parameters: InferenceRequestParameters())
            var receivedText = false
            for try await event in events {
                switch event {
                case .delta(let chunk):
                    receivedText = true
                    print(chunk, terminator: "")
                    flushStdout()
                case .result(_, let reason):
                    printFinishReasonIfNeeded(reason, receivedText: receivedText)
                case .toolCallRequested(_, let name, _):
                    print("\n[Tool call: \(name)]", terminator: "")
                    flushStdout()
                case .toolApprovalRequired(let call):
                    if toolPolicy == .ask {
                        _ = try await PlaygroundToolApprovalPrompt.resolve(
                            call: call,
                            gate: gate,
                            memory: memory,
                        )
                    } else {
                        print("\n\(PlaygroundToolEventFormatter.approvalRequired(call))", terminator: "")
                        flushStdout()
                    }
                case .toolCallCompleted(_, let name, let outcome):
                    logToolCompletion(name: name, outcome: outcome)
                case .toolHookFired:
                    break
                }
            }
        }

        private func printFinishReasonIfNeeded(
            _ reason: FinishReason,
            receivedText: Bool,
        ) {
            guard reason != .endTurn else {
                return
            }
            if receivedText {
                print()
            }
            writeToStderr("[finish reason: \(reason.rawValue)]\n")
        }

        private func logToolCompletion(name: String, outcome: ToolCallOutcome) {
            switch outcome {
            case .success:
                print("\n[Tool completed: \(name)]", terminator: "")
            case .failure(let failure):
                print("\n[Tool failed: \(name) — \(failure.resultJSON)]", terminator: "")
            }
            flushStdout()
        }
    }
}
