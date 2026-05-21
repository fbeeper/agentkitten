// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore

// MARK: - Gate inference doubles

actor GateInferenceState {
    private var started: Set<String> = []
    private var startedWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var releaseWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<String> = []
    private var cancelled: Set<String> = []

    func markStarted(_ text: String) {
        started.insert(text)
        for continuation in startedWaiters[text] ?? [] {
            continuation.resume()
        }
        startedWaiters[text] = nil
    }

    func waitUntilStarted(_ text: String) async {
        guard !started.contains(text) else {
            return
        }
        await withCheckedContinuation { continuation in
            startedWaiters[text, default: []].append(continuation)
        }
    }

    func hasStarted(_ text: String) -> Bool {
        started.contains(text)
    }

    func markCancelled(_ text: String) {
        cancelled.insert(text)
    }

    func wasCancelled(_ text: String) -> Bool {
        cancelled.contains(text)
    }

    func waitUntilReleased(_ text: String) async {
        if released.remove(text) != nil {
            return
        }
        await withCheckedContinuation { continuation in
            releaseWaiters[text] = continuation
        }
    }

    func release(_ text: String) {
        if let continuation = releaseWaiters.removeValue(forKey: text) {
            continuation.resume()
            return
        }
        released.insert(text)
    }
}

struct GateInferenceProvider: InferenceProviding {
    typealias Session = GateInferenceSession

    let state = GateInferenceState()

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> GateInferenceSession {
        GateInferenceSession(state: state)
    }

    func waitUntilStarted(_ text: String) async {
        await state.waitUntilStarted(text)
    }

    func hasStarted(_ text: String) async -> Bool {
        await state.hasStarted(text)
    }

    func wasCancelled(_ text: String) async -> Bool {
        await state.wasCancelled(text)
    }

    func release(_ text: String) async {
        await state.release(text)
    }
}

actor GateInferenceSession: InferenceSession, StructuredInferenceSession {
    private let state: GateInferenceState

    init(state: GateInferenceState) {
        self.state = state
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        let task = Task {
            await state.markStarted(message.text)
            continuation.yield(.delta("waiting \(message.text)"))
            await state.waitUntilReleased(message.text)
            guard !Task.isCancelled else {
                await state.markCancelled(message.text)
                continuation.finish()
                return
            }
            continuation.yield(.result("waiting \(message.text) done", .endTurn))
            continuation.finish()
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination {
                Task { await self.state.markCancelled(message.text) }
            }
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

// MARK: - Invalid configuration doubles

actor InvalidConfigurationState {
    private var sendCalls = 0

    func recordSend() {
        sendCalls += 1
    }

    func sendCount() -> Int {
        sendCalls
    }
}

struct InvalidConfigurationProvider: InferenceProviding {
    typealias Session = InvalidConfigurationSession

    let state = InvalidConfigurationState()

    func preflight(
        toolRegistry: ToolRegistry,
        toolSelection: ToolSelection,
    ) throws {
        throw InferenceError.unsupportedConfiguration("invalid test configuration")
    }

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> InvalidConfigurationSession {
        InvalidConfigurationSession(state: state)
    }

    func sendCount() async -> Int {
        await state.sendCount()
    }
}

actor InvalidConfigurationSession: InferenceSession, StructuredInferenceSession {
    private let state: InvalidConfigurationState

    init(state: InvalidConfigurationState) {
        self.state = state
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        await state.recordSend()
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        continuation.yield(.result("unexpected", .endTurn))
        continuation.finish()
        return stream
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        throw .generationFailed(InferenceError.invalidResponse("structured generation not supported"))
    }
}

// MARK: - Configuration recording doubles

actor ConfigurationRecordingState {
    private var configurations: [InferenceConfiguration] = []

    func record(_ configuration: InferenceConfiguration) {
        configurations.append(configuration)
    }

    func configurationsSnapshot() -> [InferenceConfiguration] {
        configurations
    }
}

struct ConfigurationRecordingProvider: InferenceProviding {
    typealias Session = ConfigurationRecordingSession

    let state = ConfigurationRecordingState()

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> ConfigurationRecordingSession {
        _ = systemPrompt
        _ = toolRuntime
        return ConfigurationRecordingSession(state: state)
    }

    func recordedConfigurations() async -> [InferenceConfiguration] {
        await state.configurationsSnapshot()
    }
}

actor ConfigurationRecordingSession: InferenceSession, StructuredInferenceSession {
    private let state: ConfigurationRecordingState

    init(state: ConfigurationRecordingState) {
        self.state = state
    }

    func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        await state.record(parameters.configuration)
        let (stream, continuation) = AsyncThrowingStream<InferenceEvent<String>, Error>.makeStream()
        continuation.yield(.result("ok", .endTurn))
        continuation.finish()
        return stream
    }

    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws(StructuredGenerationError) -> StructuredInferenceStream<T> {
        throw .generationFailed(InferenceError.invalidResponse("structured generation not supported"))
    }
}
