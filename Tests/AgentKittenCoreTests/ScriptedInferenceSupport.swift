// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import AgentKittenCore

actor SharedScript {
    private let responses: [MockResponse]
    private let structuredResponses: [MockResponse]
    private var responseIndex = 0
    private var structuredIndex = 0
    private var executionSessionIDs: [UUID] = []
    private var structuredSessionIDs: [UUID] = []
    private var promptsBySessionID: [UUID: String?] = [:]
    private var promptLog: [String?] = []
    private var structuredPromptLog: [String] = []

    init(
        responses: [MockResponse],
        structuredResponses: [MockResponse]
    ) {
        self.responses = responses
        self.structuredResponses = structuredResponses
    }

    func nextExecutionResponse(sessionID: UUID, systemPrompt: String?) -> MockResponse {
        promptsBySessionID[sessionID] = systemPrompt
        promptLog.append(systemPrompt)
        executionSessionIDs.append(sessionID)
        let response = responses[responseIndex % responses.count]
        responseIndex += 1
        return response
    }

    func nextStructuredResponse(
        sessionID: UUID,
        prompt: String,
        systemPrompt: String?
    ) throws(StructuredGenerationError) -> MockResponse {
        promptsBySessionID[sessionID] = systemPrompt
        promptLog.append(systemPrompt)
        structuredPromptLog.append(prompt)
        structuredSessionIDs.append(sessionID)
        guard !structuredResponses.isEmpty else {
            throw StructuredGenerationError.generationFailed(
                ScriptedInferenceError.noStructuredResponsesConfigured
            )
        }
        let response = structuredResponses[structuredIndex % structuredResponses.count]
        structuredIndex += 1
        return response
    }

    func executionSessionUseCount() -> Int {
        Set(executionSessionIDs).count
    }

    func structuredSessionUseCount() -> Int {
        Set(structuredSessionIDs).count
    }

    func prompt(for sessionID: UUID) -> String? {
        promptsBySessionID[sessionID] ?? nil
    }

    func latestPrompt() -> String? {
        promptLog.last ?? nil
    }

    func latestStructuredUserPrompt() -> String? {
        structuredPromptLog.last
    }
}

actor ScriptedInferenceSession: InferenceSession, StructuredInferenceSession {
    private let script: SharedScript
    private let sessionID = UUID()
    private let systemPrompt: String?
    private let toolRuntime: ToolRuntime

    init(
        script: SharedScript,
        systemPrompt: String?,
        toolRuntime: ToolRuntime
    ) {
        self.script = script
        self.systemPrompt = systemPrompt
        self.toolRuntime = toolRuntime
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        // Scripted sessions intentionally ignore `toolSelection`: they are test
        // fixtures for explicit scripted responses, not provider-parity mocks.
        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
            toolStepBudget: parameters.toolStepBudget,
            context: parameters.toolExecutionContext
        )
        let response = await script.nextExecutionResponse(
            sessionID: sessionID,
            systemPrompt: systemPrompt
        )
        return Self.stream(
            for: response,
            toolTurnRuntime: toolTurnRuntime
        )
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        // Scripted sessions intentionally ignore `toolSelection`: scripted tool
        // calls should still execute unless the test explicitly scripts otherwise.
        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
            toolStepBudget: parameters.toolStepBudget,
            context: parameters.toolExecutionContext
        )
        let response = try await script.nextStructuredResponse(
            sessionID: sessionID,
            prompt: prompt,
            systemPrompt: systemPrompt
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let json = try await Self.structuredJSON(
                        for: response,
                        toolTurnRuntime: toolTurnRuntime,
                        continuation: continuation
                    )
                    let value = try Self.decodeStructuredValue(T.self, from: json)
                    continuation.yield(.result(value, .endTurn))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

extension ScriptedInferenceSession {
    private static func stream(
        for response: MockResponse,
        toolTurnRuntime: ToolTurnRuntime
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
                            argumentsJSON: argumentsJSON
                        )
                        try await streamToolCall(
                            call: call,
                            thenRespond: thenRespond,
                            toolTurnRuntime: toolTurnRuntime,
                            continuation: continuation
                        )
                    }
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func streamToolCall(
        call: PendingToolCall,
        thenRespond: String,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: InferenceStream.Continuation
    ) async throws {
        continuation.yield(.toolCallRequested(id: call.id, name: call.name, argumentsJSON: call.argumentsJSON))
        let outcome = await toolTurnRuntime.invoke(
            call,
            onApprovalRequired: { pendingCall in
                continuation.yield(.toolApprovalRequired(call: pendingCall))
            }
        )
        continuation.yield(
            .toolCallCompleted(
                id: call.id,
                name: call.name,
                outcome: outcome
            )
        )
        try await streamWords(thenRespond, into: continuation)
    }

    private static func streamWords(
        _ text: String,
        into continuation: InferenceStream.Continuation
    ) async throws {
        let words = text.split(separator: " ")
        for (index, word) in words.enumerated() {
            try Task.checkCancellation()
            let chunk = (index == 0 ? "" : " ") + String(word)
            continuation.yield(.delta(chunk))
        }
        continuation.yield(.result(text, .endTurn))
        continuation.finish()
    }

    private static func decodeStructuredValue<T: Decodable>(
        _ type: T.Type,
        from json: String
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
        continuation: StructuredInferenceStream<T>.Continuation
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
                argumentsJSON: argumentsJSON
            )
            return try await structuredToolResponse(
                pending,
                thenRespond: thenRespond,
                toolTurnRuntime: toolTurnRuntime,
                continuation: continuation
            )
        }
    }

    private static func structuredToolResponse<T: Sendable>(
        _ pending: PendingToolCall,
        thenRespond: String,
        toolTurnRuntime: ToolTurnRuntime,
        continuation: StructuredInferenceStream<T>.Continuation
    ) async throws(StructuredGenerationError) -> String {
        continuation.yield(
            .toolCallRequested(
                id: pending.id,
                name: pending.name,
                argumentsJSON: pending.argumentsJSON
            )
        )
        let outcome = await toolTurnRuntime.invoke(
            pending,
            onApprovalRequired: { pendingCall in
                continuation.yield(.toolApprovalRequired(call: pendingCall))
            }
        )
        continuation.yield(
            .toolCallCompleted(
                id: pending.id,
                name: pending.name,
                outcome: outcome
            )
        )
        switch outcome {
        case .success:
            return thenRespond
        case .failure(.denied):
            return thenRespond
        case .failure(.stepLimitExceeded):
            throw StructuredGenerationError.generationFailed(ScriptedInferenceError.stepLimitExceeded)
        case .failure(.execution(let message)):
            throw StructuredGenerationError.generationFailed(
                InferenceError.invalidResponse(message)
            )
        }
    }
}

private enum ScriptedInferenceError: Error {
    case noStructuredResponsesConfigured
    case stepLimitExceeded
}
