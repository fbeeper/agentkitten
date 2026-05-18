// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

@Suite("Agent Session")
struct AgentSessionTests {
    @Test func makeSession_usesDefaultAndOverrideOwners() {
        let agent = Agent(
            agentId: "assistant",
            providerRegistry: ProviderRegistry(default: ScriptedInferenceProvider()),
            behavior: .test(),
            owner: "default-user",
        )

        let defaultSession = agent.makeSession()
        let overrideSession = agent.makeSession(for: "override-user")

        #expect(defaultSession.agentID == agent.agentId)
        #expect(defaultSession.ownerID == "default-user")
        #expect(overrideSession.agentID == agent.agentId)
        #expect(overrideSession.ownerID == "override-user")
        #expect(defaultSession.sessionID != overrideSession.sessionID)
    }

    @Test func sessionsKeepTracesAndConversationReuseIndependent() async throws {
        let provider = ScriptedInferenceProvider(
            responses: [
                .success("First response"),
                .success("Second response"),
            ],
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let firstSession = agent.makeSession()
        let secondSession = agent.makeSession()

        let firstTurn = try await firstSession.send("first")
        _ = try await collectEvents(from: firstTurn)
        let secondTurn = try await secondSession.send("second")
        _ = try await collectEvents(from: secondTurn)

        let firstEntries = await firstSession.trace.snapshot()
        let secondEntries = await secondSession.trace.snapshot()

        #expect(await provider.script.executionSessionUseCount() == 2)
        #expect(firstEntries.allSatisfy { $0.invocationID == firstTurn.id })
        #expect(secondEntries.allSatisfy { $0.invocationID == secondTurn.id })
        #expect(!firstEntries.contains { $0.invocationID == secondTurn.id })
        #expect(!secondEntries.contains { $0.invocationID == firstTurn.id })
    }

    @Test func queuedSessionSerializesQueueWhileSecondSessionRunsIndependently() async throws {
        let provider = GateInferenceProvider()
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let firstSession = agent.makeQueuedSession()
        let secondSession = agent.makeQueuedSession()

        let firstTurn = await firstSession.send("a1")
        let firstTask = Task { try await collectEvents(from: firstTurn) }
        await provider.waitUntilStarted("a1")

        let queuedTurn = await firstSession.send("a2")
        let queuedTask = Task { try await collectEvents(from: queuedTurn) }

        let secondTurn = await secondSession.send("b1")
        let secondTask = Task { try await collectEvents(from: secondTurn) }
        await provider.waitUntilStarted("b1")

        #expect(await provider.hasStarted("a2") == false)

        await provider.release("b1")
        _ = try await secondTask.value
        #expect(await provider.hasStarted("a2") == false)

        await provider.release("a1")
        _ = try await firstTask.value
        await provider.waitUntilStarted("a2")

        await provider.release("a2")
        _ = try await queuedTask.value
    }

    @Test func invalidConversationConfigurationFailsBeforeSessionSend() async throws {
        let provider = InvalidConfigurationProvider()
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )

        do {
            _ = try await collectEvents(from: await agent.makeSession().send("hello"))
            Issue.record("Expected invalid conversation configuration to fail")
        } catch let error as InferenceError {
            guard case .unsupportedConfiguration(let message) = error else {
                Issue.record("Expected unsupportedConfiguration, got \(error)")
                return
            }
            #expect(message.contains("invalid test configuration"))
            #expect(await provider.sendCount() == 0)
        }
    }

    @Test func send_defaultPathUsesBehaviorDefaultInferenceConfiguration() async throws {
        let provider = ConfigurationRecordingProvider()
        let behavior = AgentBehavior(
            systemPrompt: "Test",
            phaseBehaviors: .init(base: .init(inferenceConfiguration: InferenceConfiguration(
                temperature: 0.9,
            ))),
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: behavior,
        )

        _ = try await collectEvents(from: await agent.makeSession().send("hello"))

        #expect(
            await provider.recordedConfigurations() == [
                InferenceConfiguration(temperature: 0.9),
            ],
        )
    }

    @Test func send_explicitTurnOverridesUsesSuppliedInferenceConfiguration() async throws {
        let provider = ConfigurationRecordingProvider()
        let behavior = AgentBehavior(
            systemPrompt: "Test",
            phaseBehaviors: .init(base: .init(inferenceConfiguration: InferenceConfiguration(
                temperature: 0.1,
            ))),
        )
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: behavior,
        )
        let turnOverrides = TurnOverrides(
            inferenceConfiguration: InferenceConfiguration(
                temperature: 0.7,
            ),
        )

        _ = try await collectEvents(from: await agent.makeSession().send(
            "hello",
            turnOverrides: turnOverrides,
        ))

        #expect(
            await provider.recordedConfigurations() == [
                InferenceConfiguration(temperature: 0.7),
            ],
        )
    }
}

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

actor InvalidConfigurationState {
    private var sendCalls = 0

    func recordSend() {
        sendCalls += 1
    }

    func sendCount() -> Int {
        sendCalls
    }
}

actor ConfigurationRecordingState {
    private var configurations: [InferenceConfiguration] = []

    func record(_ configuration: InferenceConfiguration) {
        configurations.append(configuration)
    }

    func configurationsSnapshot() -> [InferenceConfiguration] {
        configurations
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
