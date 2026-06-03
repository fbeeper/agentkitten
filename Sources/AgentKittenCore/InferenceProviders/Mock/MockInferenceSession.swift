// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Logging

private let logger = Logger(label: "agentKitten.core.mockInferenceSession")

/// A mock ``InferenceSession`` that cycles through canned responses.
///
/// Used by ``MockInferenceProvider``. Simulates streaming by yielding the
/// response word-by-word with a small artificial delay. Cycles through the
/// provided responses in order, wrapping around when exhausted.
///
/// Tool calls go through the coordinated ``ToolRuntime`` path provided at
/// session creation — the same provider-facing runtime used by all types.
///
/// Public so library consumers can use it in their own test targets.
///
/// The same actor also supports ``StructuredInferenceSession`` when configured
/// with `structuredResponses`.
public actor MockInferenceSession: InferenceSession {
    private let responses: [MockResponse]
    private let structuredResponses: [String]
    private let structuredMockResponses: [MockResponse]
    private var callIndex: Int = 0
    private var structuredIndex: Int = 0
    private var estimatedContextTokens: Int = 0
    private let toolRuntime: ToolRuntime
    private let operationGate = SingleFlightOperationGate<InferenceSessionOperationKind> {
        InferenceError.concurrentOperationInProgress(active: $0)
    }

    /// Creates a mock session with the given canned responses.
    ///
    /// Uses an empty tool registry. Suitable for testing text-only flows.
    /// For tool call tests, use ``MockInferenceProvider`` with tools registered on ``Agent``.
    ///
    /// If `responses` is empty a fallback success response is substituted and an
    /// error is logged, so no crash occurs.
    ///
    /// - Parameters:
    ///   - responses: Canned streaming responses for regular session turns.
    ///   - structuredResponses: Pre-encoded JSON strings returned by structured generation.
    public init(
        responses: [MockResponse],
        structuredResponses: [String] = [],
        structuredMockResponses: [MockResponse] = [],
    ) {
        if responses.isEmpty {
            logger.error("MockInferenceSession initialized with empty responses; using fallback.")
            self.responses = [.success("This is a mock response.")]
        } else {
            self.responses = responses
        }
        self.structuredResponses = structuredResponses
        self.structuredMockResponses = structuredMockResponses
        let toolBehavior = ToolBehavior()
        toolRuntime = ToolRuntime(
            toolDefinition: .noTools,
            toolBehavior: toolBehavior,
        )
    }

    /// Internal init used by ``MockInferenceProvider`` — wires in the full tool runtime.
    init(
        responses: [MockResponse],
        structuredResponses: [String] = [],
        structuredMockResponses: [MockResponse] = [],
        toolRuntime: ToolRuntime,
    ) {
        if responses.isEmpty {
            logger.error("MockInferenceSession initialized with empty responses; using fallback.")
            self.responses = [.success("This is a mock response.")]
        } else {
            self.responses = responses
        }
        self.structuredResponses = structuredResponses
        self.structuredMockResponses = structuredMockResponses
        self.toolRuntime = toolRuntime
    }

    /// Streams the next canned response, executing tool calls through the executor.
    public func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        let lease = try operationGate.begin(.run)
        estimatedContextTokens += Self.estimatedTokens(message.text)
        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
            toolStepBudget: parameters.toolStepBudget,
            context: parameters.toolExecutionContext,
            toolSelection: parameters.toolSelection,
        )
        let response = responses[callIndex % responses.count]
        callIndex += 1
        return Self.stream(for: response, toolTurnRuntime: toolTurnRuntime, lease: lease)
    }

    private static func stream(
        for response: MockResponse,
        toolTurnRuntime: ToolTurnRuntime,
        lease: SingleFlightOperationGate<InferenceSessionOperationKind>.Lease,
    ) -> InferenceStream {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch response {
                    case .success(let text):
                        try await streamWords(text, into: continuation)

                    case .failure(let error):
                        continuation.finish(throwing: error)

                    case .toolCall(let name, let argumentsJSON, let thenRespond):
                        let call = PendingToolCall(
                            id: UUID().uuidString,
                            name: name,
                            argumentsJSON: argumentsJSON,
                        )
                        try await streamToolCall(
                            call: call,
                            thenRespond: thenRespond,
                            toolTurnRuntime: toolTurnRuntime,
                            continuation: continuation,
                        )
                    }
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                lease.end()
                task.cancel()
            }
        }
    }

    /// Streams a single tool call interaction.
    private static func streamToolCall(
        call: PendingToolCall,
        thenRespond: String,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: InferenceStream.Continuation,
    ) async throws {
        try Task.checkCancellation()
        continuation.yield(.toolCallRequested(id: call.id, name: call.name, argumentsJSON: call.argumentsJSON))
        try Task.checkCancellation()
        let outcome = await toolOutcome(
            for: call,
            toolTurnRuntime: toolTurnRuntime,
            onApprovalRequired: { pendingCall in
                continuation.yield(.toolApprovalRequired(call: pendingCall))
            },
        )
        continuation.yield(.toolCallCompleted(
            id: call.id,
            name: call.name,
            outcome: outcome,
        ))
        try await streamWords(thenRespond, into: continuation)
    }

    private static func streamWords(
        _ text: String,
        into continuation: InferenceStream.Continuation,
    ) async throws {
        let words = text.split(separator: " ")
        for (index, word) in words.enumerated() {
            try Task.checkCancellation()
            let chunk = (index == 0 ? "" : " ") + String(word)
            continuation.yield(.delta(chunk))
            try await Task.sleep(for: .milliseconds(50))
        }
        continuation.yield(.result(text, .endTurn))
        continuation.finish()
    }
}

extension MockInferenceSession: StructuredInferenceSession {
    public func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws
        -> StructuredInferenceStream<T> {
        let lease = try operationGate.begin(.generate)
        estimatedContextTokens += Self.estimatedTokens(prompt)
        do {
            let toolTurnRuntime = toolRuntime.makeTurnRuntime(
                toolStepBudget: parameters.toolStepBudget,
                context: parameters.toolExecutionContext,
                toolSelection: parameters.toolSelection,
            )
            let response = try structuredResponse()
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let json = try await Self.structuredJSON(
                            for: response,
                            toolTurnRuntime: toolTurnRuntime,
                            continuation: continuation,
                        )
                        let value = try Self.decodeStructuredValue(T.self, from: json)
                        continuation.yield(.result(value, .endTurn))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    lease.end()
                    task.cancel()
                }
            }
        } catch {
            lease.end()
            throw error
        }
    }
}

extension MockInferenceSession {
    public func contextUsage() async throws -> ContextUsage {
        let lease = try operationGate.begin(.contextUsage)
        defer {
            lease.end()
        }
        return ContextUsage(
            contextTokens: .tokens(UInt(estimatedContextTokens)),
            contextSize: 100,
        )
    }

    private static func estimatedTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }
}

extension MockInferenceSession: ContextCompactableSession {
    public func compactionEntries() -> [RenderedSessionEntry] {
        []
    }

    public func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int,
    ) async throws -> ContextCompactionResult {
        let before = ContextUsage(contextTokens: .tokens(UInt(estimatedContextTokens)), contextSize: 100)
        estimatedContextTokens = min(estimatedContextTokens, max(0, preservedRecentTurnCount * 10))
        let after = ContextUsage(contextTokens: .tokens(UInt(estimatedContextTokens)), contextSize: 100)
        return .compacted(ContextCompactionResult.Compacted(usageBefore: before, usageAfter: after))
    }
}

extension MockInferenceSession {
    private func structuredResponse() throws(StructuredGenerationError) -> MockResponse {
        if !structuredMockResponses.isEmpty {
            let response = structuredMockResponses[structuredIndex % structuredMockResponses.count]
            structuredIndex += 1
            return response
        }
        if !structuredResponses.isEmpty {
            let response = structuredResponses[structuredIndex % structuredResponses.count]
            structuredIndex += 1
            return .success(response)
        }
        throw StructuredGenerationError.generationFailed(
            MockStructuredGenerationError.noResponsesConfigured,
        )
    }

    private static func decodeStructuredValue<T: Decodable>(
        _ type: T.Type,
        from json: String,
    ) throws(StructuredGenerationError) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw StructuredGenerationError.decodingFailed(error)
        }
    }

    private static func structuredJSON<T: Sendable>(
        for response: MockResponse,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: StructuredInferenceStream<T>.Continuation,
    ) async throws(StructuredGenerationError) -> String {
        switch response {
        case .success(let text):
            return text
        case .failure(let error):
            throw StructuredGenerationError.generationFailed(error)
        case .toolCall(let name, let argumentsJSON, let thenRespond):
            let pending = PendingToolCall(
                id: UUID().uuidString,
                name: name,
                argumentsJSON: argumentsJSON,
            )
            return try await structuredToolResponse(
                pending,
                thenRespond: thenRespond,
                toolTurnRuntime: toolTurnRuntime,
                continuation: continuation,
            )
        }
    }

    private static func structuredToolResponse<T: Sendable>(
        _ pending: PendingToolCall,
        thenRespond: String,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: StructuredInferenceStream<T>.Continuation,
    ) async throws(StructuredGenerationError) -> String {
        continuation.yield(
            .toolCallRequested(
                id: pending.id,
                name: pending.name,
                argumentsJSON: pending.argumentsJSON,
            ),
        )
        let outcome = await toolOutcome(
            for: pending,
            toolTurnRuntime: toolTurnRuntime,
            onApprovalRequired: { pendingCall in
                continuation.yield(.toolApprovalRequired(call: pendingCall))
            },
        )
        continuation.yield(
            .toolCallCompleted(
                id: pending.id,
                name: pending.name,
                outcome: outcome,
            ),
        )
        switch outcome {
        case .success:
            return thenRespond
        case .failure(.denied):
            return thenRespond
        case .failure(.stepLimitExceeded):
            throw StructuredGenerationError.generationFailed(MockStructuredGenerationError.stepLimitExceeded)
        case .failure(.execution(let message)):
            throw StructuredGenerationError.generationFailed(
                InferenceError.invalidResponse(message),
            )
        }
    }

    private static func toolOutcome(
        for pending: PendingToolCall,
        toolTurnRuntime: ToolTurnRuntime,
        onApprovalRequired: @escaping @Sendable (PendingToolCall) async -> Void,
    ) async -> ToolCallOutcome {
        await toolTurnRuntime.invoke(
            pending,
            onApprovalRequired: onApprovalRequired,
        )
    }
}

private enum MockStructuredGenerationError: Error, CustomStringConvertible {
    case noResponsesConfigured
    case stepLimitExceeded

    var description: String {
        switch self {
        case .noResponsesConfigured:
            """
            MockInferenceSession has no configured structured responses. \
            Pass structuredResponses to MockInferenceProvider.
            """
        case .stepLimitExceeded:
            "step limit exceeded"
        }
    }
}
