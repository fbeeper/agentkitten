// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation

private enum StructuredResultEncodingError: Error {
    case invalidUTF8
}

func rawTraceEntries(
    for invocationID: InvocationID,
    on trace: AgentTrace,
) async -> [AgentTraceEntry] {
    await trace.snapshot().filter { $0.invocationID == invocationID }
}

func rawTraceEntries(
    for invocationID: InvocationID,
    on session: AgentSession,
) async -> [AgentTraceEntry] {
    await rawTraceEntries(for: invocationID, on: session.trace)
}

func rawTraceEntries(
    for invocationID: InvocationID,
    on session: AgentQueuedSession,
) async -> [AgentTraceEntry] {
    await rawTraceEntries(for: invocationID, on: session.trace)
}

func directTurnEntries(
    for invocationID: InvocationID,
    on trace: AgentTrace,
) async -> [AgentTraceEntry] {
    await rawTraceEntries(for: invocationID, on: trace).filter {
        switch $0.kind {
        case .executionPreparation, .conversationResolved, .contextCompaction:
            false
        default:
            true
        }
    }
}

func directTurnEntries(
    for invocationID: InvocationID,
    on session: AgentSession,
) async -> [AgentTraceEntry] {
    await directTurnEntries(for: invocationID, on: session.trace)
}

func directTurnEntryKinds(in entries: [AgentTraceEntry]) -> [AgentTraceEntry.Kind] {
    entries.compactMap {
        switch $0.kind {
        case .executionPreparation, .conversationResolved, .contextCompaction:
            nil
        default:
            $0.kind
        }
    }
}

func executionPreparationEntry(
    for invocationID: InvocationID,
    on session: AgentSession,
) async -> AgentTraceEntry.Kind.ExecutionPreparationInfo? {
    let entries = await rawTraceEntries(for: invocationID, on: session)
    for entry in entries {
        if case .executionPreparation(let info) = entry.kind {
            return info
        }
    }
    return nil
}

func conversationResolvedEntry(
    for invocationID: InvocationID,
    on session: AgentSession,
) async -> AgentTraceEntry.Kind.ConversationResolvedInfo? {
    let entries = await rawTraceEntries(for: invocationID, on: session)
    for entry in entries {
        if case .conversationResolved(let info) = entry.kind {
            return info
        }
    }
    return nil
}

func structuredResultTypeLabel<Result>(
    for _: Result.Type,
) -> String {
    String(describing: Result.self)
}

func structuredResultJSON<Result: Encodable>(
    for result: Result,
) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(result)
    guard let string = String(data: data, encoding: .utf8) else {
        throw StructuredResultEncodingError.invalidUTF8
    }
    return string
}

func whereFailedTurnCompleted(_ kind: AgentTraceEntry.Kind) -> Bool {
    if case .turnCompleted(.failed) = kind {
        return true
    }
    return false
}

actor HangingInferenceState {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    func markStarted() {
        started = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

struct HangingInferenceProvider: InferenceProviding {
    typealias Session = HangingInferenceSession

    let state = HangingInferenceState()

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> HangingInferenceSession {
        HangingInferenceSession(state: state)
    }

    func waitUntilStarted() async {
        await state.waitUntilStarted()
    }
}

actor HangingInferenceSession: InferenceSession, StructuredInferenceSession {
    private let state: HangingInferenceState

    init(state: HangingInferenceState) {
        self.state = state
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        await state.markStarted()
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        let task = Task {
            do {
                continuation.yield(.delta("waiting"))
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(10))
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        throw .generationFailed(InferenceError.invalidResponse("structured generation not supported"))
    }
}
