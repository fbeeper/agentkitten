// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import ArgumentParser
import Foundation

// MARK: - Output type

/// A simple structured output type used by the `classify` Playground command.
private struct ClassificationResult: Codable, Sendable, JSONSchemaProviding {
    let category: String
    let confidence: Double
    let reasoning: String
    let currentTime: CurrentTimeTool.Output

    static var jsonSchema: JSONSchema {
        .object(
            properties: [
                "category": .string(description: "Short label: e.g. 'question', 'request', 'complaint'."),
                "confidence": .number(description: "Confidence score between 0.0 and 1.0."),
                "reasoning": .string(description: "One sentence explaining the classification."),
                "currentTime": .object(
                    properties: [
                        "iso8601": .string(
                            description: "The current time as returned by the current_time tool in ISO 8601 format.",
                        ),
                        "readable": .string(
                            description: "The current time as returned by the current_time tool in readable format.",
                        ),
                    ],
                    required: ["iso8601", "readable"],
                ),
            ],
            required: ["category", "confidence", "reasoning", "currentTime"],
        )
    }
}

// MARK: - Command

extension Playground {
    /// Structured output demo: classifies the input and prints the decoded result.
    ///
    /// Exercises ``StructuredInferenceSession`` end-to-end: schema injection,
    /// JSON mode, streaming accumulation, and `Decodable` decode.
    struct Classify: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Classify a prompt via structured output and print the decoded result.",
        )

        @Option(name: .long, help: "The text to classify.")
        var prompt: String

        @Option(name: .long, help: "Inference provider.")
        var provider: ProviderOption = .preferred

        @OptionGroup var openAIOptions: OpenAIProviderOptions

        @Option(name: .long, help: "Tool execution policy: approve, ask, or deny.")
        var toolPolicy: ToolPolicyOption = .approve

        func run() async throws {
            print("AgentKitten Playground v\(AgentKitten.version)")
            print("Classifying: \(prompt)")
            let policy = PlaygroundToolApprovalPrompt.configuredPolicy(for: toolPolicy)
            if provider == .mock {
                try await classifyMock(policy: policy)
                return
            }
            let runtime = PlaygroundSessionFactory.makeToolRuntime(
                tools: [AnyAgentTool(CurrentTimeTool())],
                policy: policy,
            )
            let session = try PlaygroundSessionFactory.makeSession(
                for: provider,
                systemPrompt: systemPrompt(),
                runtime: runtime,
                openAIBaseURL: openAIOptions.baseURL,
                openAIModel: openAIOptions.model,
            )
            try await classify(session: session, gate: runtime.approvalGate)
        }

        private func systemPrompt() -> String {
            """
            You are a text classifier. Classify the user's input.
            Use the current_time tool and copy its exact output into the currentTime field.
            """
        }

        private func classifyMock(policy: AnyToolExecutionPolicy) async throws {
            let runtime = PlaygroundSessionFactory.makeToolRuntime(
                tools: [AnyAgentTool(MockCurrentTimeTool())],
                policy: policy,
            )
            let session = InferenceProvider(
                MockInferenceProvider(
                    structuredMockResponses: [
                        .toolCall(
                            name: MockCurrentTimeTool.name,
                            argumentsJSON: "{}",
                            thenRespond: mockClassificationResponse,
                        ),
                    ],
                ),
            ).makeSession(
                systemPrompt: systemPrompt(),
                toolRuntime: runtime,
                toolSelection: .all,
                inferenceContext: .empty,
            )
            try await classify(session: session, gate: runtime.approvalGate)
        }

        private func classify(
            session: any StructuredInferenceSession,
            gate: ToolApprovalGate,
        ) async throws {
            let memory = PlaygroundToolApprovalMemory()
            do {
                let stream: StructuredInferenceStream<ClassificationResult> =
                    try await session.generateStream(prompt: prompt, parameters: InferenceRequestParameters())
                var result: ClassificationResult?
                for try await event in stream {
                    switch event {
                    case .delta:
                        break
                    case .toolCallRequested(_, let name, _):
                        print("Tool:       \(name)")
                    case .toolApprovalRequired(let call):
                        _ = try await PlaygroundToolApprovalPrompt.resolve(
                            call: call,
                            gate: gate,
                            memory: memory,
                        )
                    case .toolCallCompleted(_, _, let outcome):
                        logToolOutcome(outcome)
                    case .result(let structured, _):
                        result = structured
                    case .toolHookFired:
                        break
                    }
                }
                guard let result else {
                    writeToStderr("[error: structured generation ended without a result]\n")
                    return
                }
                printResult(result)
            } catch StructuredGenerationError.decodingFailed(let error) {
                writeToStderr("[error: failed to decode response — \(error)]\n")
            } catch StructuredGenerationError.generationFailed(let error) {
                writeToStderr("[error: generation failed — \(error)]\n")
            }
        }

        private func logToolOutcome(_ outcome: ToolCallOutcome) {
            guard case .failure(let failure) = outcome else {
                return
            }
            print("Tool error: \(failure.resultJSON)")
        }

        private func printResult(_ result: ClassificationResult) {
            print("Category:   \(result.category)")
            print("Confidence: \(String(format: "%.0f%%", result.confidence * 100))")
            print("Reasoning:  \(result.reasoning)")
            print("Time:       \(result.currentTime.readable)")
            print("Time ISO:   \(result.currentTime.iso8601)")
        }
    }
}

private struct MockCurrentTimeTool: AgentTool {
    typealias Arguments = CurrentTimeTool.Arguments
    typealias Output = CurrentTimeTool.Output

    static let name = CurrentTimeTool.name
    static let defaultDescription = CurrentTimeTool.defaultDescription

    var schema: ToolSchema {
        CurrentTimeTool().schema
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(
            iso8601: "2026-03-27T12:34:56Z",
            readable: "March 27, 2026 at 12:34:56 PM UTC",
        )
    }
}

private let mockClassificationResponse = #"""
{
  "category": "mock-request",
  "confidence": 0.01,
  "reasoning": "Mock fallback response: canned JSON returned by MockInferenceProvider for Playground demos.",
  "currentTime": {
    "iso8601": "2026-03-27T12:34:56Z",
    "readable": "March 27, 2026 at 12:34:56 PM UTC"
  }
}
"""#
