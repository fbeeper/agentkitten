// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
import AgentKittenInferenceSupport
import Foundation
import FoundationModels
import os

private let logger = Logger(subsystem: "AgentKittenCore", category: "AppleInferenceSession")

/// A per-conversation model connection backed by Apple's on-device LanguageModelSession.
///
/// One `AppleInferenceSession` is created per ``Conversation``. Apple's
/// `LanguageModelSession` maintains its own turn history internally, so no
/// prompt reconstruction is needed across turns — each ``send(_:configuration:)``
/// call appends directly to the session.
///
/// The session is an actor to satisfy `Sendable` and ensure thread-safe access
/// to session state.
///
/// In-flight request cancellation is owned by stream termination, not by
/// session deinitialization. The worker task retains the session while active,
/// so callers must stop iterating the returned stream to cancel the request.
///
/// ## Tool calling
/// Tools registered on ``ToolRuntime`` are bridged via ``AppleBridgedTool``
/// and forwarded to `LanguageModelSession` at init time. The framework manages the
/// tool-call loop internally; ``AppleBridgedTool`` emits ``InferenceEvent/toolCallRequested``
/// and ``InferenceEvent/toolCallCompleted(_:_:_:)`` in real time through a shared
/// ``ToolEventRelay`` as each tool executes, so consumers observe progress immediately
/// rather than after the full turn completes.
@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
public actor AppleInferenceSession: InferenceSession {
    var languageSession: LanguageModelSession
    let model: SystemLanguageModel
    let eventRelay: ToolEventRelay
    let toolRuntime: ToolRuntime
    let toolBridgeRuntime: AppleToolBridgeRuntime
    let bridgedTools: [any Tool]
    let historyRenderingConfiguration: HistoryRenderingConfiguration
    let operationGate = SingleFlightOperationGate<InferenceSessionOperationKind> {
        InferenceError.concurrentOperationInProgress(active: $0)
    }

    /// Creates a session, bridging all tools in the runtime to
    /// `LanguageModelSession`.
    ///
    /// AgentKitten conversations run provider preflight before calling this initializer.
    /// Callers that instantiate `AppleInferenceSession` directly should do the same.
    /// If unsupported tools are still present here, they are asserted/logged and
    /// dropped from the bridged Foundation Models session.
    init(
        systemPrompt: String?,
        model: SystemLanguageModel,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        historyRenderingConfiguration: HistoryRenderingConfiguration = HistoryRenderingConfiguration(),
    ) {
        self.historyRenderingConfiguration = historyRenderingConfiguration
        let eventRelay = ToolEventRelay()
        self.eventRelay = eventRelay
        self.toolRuntime = toolRuntime
        let toolBridgeRuntime = AppleToolBridgeRuntime()
        self.toolBridgeRuntime = toolBridgeRuntime
        let bridged = Self.bridgeTools(
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            toolBridgeRuntime: toolBridgeRuntime,
            eventRelay: eventRelay,
        )
        bridgedTools = bridged
        self.model = model
        languageSession = Self.makeLanguageSession(
            systemPrompt: systemPrompt,
            model: model,
            bridgedTools: bridged,
        )
    }

    /// Creates a session that continues from a prior session's transcript, rebinding tools.
    ///
    /// Use this initializer when rebuilding a session after a tool-availability change.
    /// The prior session's turn history is preserved via its `Transcript`. The system
    /// prompt is carried forward within the transcript by Foundation Models; no separate
    /// `instructions:` parameter is accepted by this `LanguageModelSession` initializer.
    init(
        transcript: FoundationModels.Transcript,
        model: SystemLanguageModel,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        historyRenderingConfiguration: HistoryRenderingConfiguration = HistoryRenderingConfiguration(),
    ) {
        self.historyRenderingConfiguration = historyRenderingConfiguration
        let eventRelay = ToolEventRelay()
        self.eventRelay = eventRelay
        self.toolRuntime = toolRuntime
        let toolBridgeRuntime = AppleToolBridgeRuntime()
        self.toolBridgeRuntime = toolBridgeRuntime
        let bridged = Self.bridgeTools(
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            toolBridgeRuntime: toolBridgeRuntime,
            eventRelay: eventRelay,
        )
        bridgedTools = bridged
        self.model = model
        languageSession = LanguageModelSession(model: model, tools: bridged, transcript: transcript)
    }

    /// Returns the current turn transcript, captured under actor isolation.
    func captureTranscript() -> FoundationModels.Transcript {
        languageSession.transcript
    }

    func replaceTranscript(_ transcript: FoundationModels.Transcript) {
        languageSession = LanguageModelSession(
            model: model,
            tools: bridgedTools,
            transcript: transcript,
        )
    }

    private static func bridgeTools(
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        toolBridgeRuntime: AppleToolBridgeRuntime,
        eventRelay: ToolEventRelay,
    ) -> [any Tool] {
        let selectedTools = toolRuntime.tools(matching: toolSelection)
        let bridged: [any Tool] = selectedTools
            .filter {
                $0.capabilities.producesOnly(
                    AppleToolResultSupport.supportedKinds,
                )
            }
            .compactMap {
                AppleBridgedTool(
                    agentTool: $0,
                    toolBridgeRuntime: toolBridgeRuntime,
                    eventRelay: eventRelay,
                    rationaleDescription: toolRuntime.rationaleSchemaDescription,
                )
            }
        if bridged.count < selectedTools.count {
            assertionFailure(
                "AppleInferenceSession initialized without provider preflight; unsupported tools were dropped.",
            )
            logger.error(
                """
                AppleInferenceSession initialized without provider preflight; unsupported \
                tools were dropped from the bridged Foundation Models session.
                """,
            )
        }
        return bridged
    }

    private static func makeLanguageSession(
        systemPrompt: String?,
        model: SystemLanguageModel,
        bridgedTools: [any Tool],
    ) -> LanguageModelSession {
        if bridgedTools.isEmpty {
            if let prompt = systemPrompt {
                return LanguageModelSession(model: model, instructions: Instructions(prompt))
            } else {
                return LanguageModelSession(model: model)
            }
        } else {
            let prompt = systemPrompt ?? ""
            return LanguageModelSession(model: model, tools: bridgedTools) {
                Instructions(prompt)
            }
        }
    }

    /// Runs a single inference turn and streams the model's response.
    public func run(_ message: UserMessage, parameters: InferenceRequestParameters) async throws -> InferenceStream {
        let lease = try operationGate.begin(.run)

        if let error = Self.availabilityError() {
            lease.end()
            let (stream, continuation) = InferenceStream.makeStream()
            continuation.finish(throwing: error)
            return stream
        }

        let options = GenerationOptions(
            temperature: parameters.configuration.temperature,
            maximumResponseTokens: parameters.configuration.maxTokens,
        )

        let (stream, continuation) = InferenceStream.makeStream()
        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
            toolStepBudget: parameters.toolStepBudget,
            context: parameters.toolExecutionContext,
            toolSelection: parameters.toolSelection,
        )
        await toolBridgeRuntime.beginTurn(toolTurnRuntime)
        let eventRelay = eventRelay
        let relayTurn = await eventRelay.beginTurn(continuation)
        let toolBridgeRuntime = toolBridgeRuntime
        let task = Task {
            defer {
                Task { await toolBridgeRuntime.endTurn(toolTurnRuntime) }
                Task { await eventRelay.endTurn(relayTurn) }
            }
            // Multi-user: FoundationModels has no native speaker field. When the conversation
            // has multiple participants, prepend speaker context to the system prompt at session
            // creation time (e.g. "Current speaker: \(message.sender)") rather than embedding
            // it in the message text, to avoid polluting the turn history seen by the model.
            await self.runGeneration(prompt: message.text, options: options, continuation: continuation)
        }
        // Unstructured Task: onTermination is a @Sendable sync callback; cannot await.
        continuation.onTermination = { _ in
            lease.end()
            task.cancel()
            // Consumer dropped or cancelled the stream — stop the relay forwarding to
            // this continuation so bridged tools don't yield into a finished stream.
            Task { await eventRelay.endTurn(relayTurn) }
            Task { await toolBridgeRuntime.endTurn(toolTurnRuntime) }
        }
        return stream
    }

    private func runGeneration(
        prompt: String,
        options: GenerationOptions,
        continuation: InferenceStream.Continuation,
    ) async {
        let response = languageSession.streamResponse(to: Prompt(prompt), options: options)
        // FoundationModels streams cumulative text snapshots, not deltas.
        // Track how many characters have been forwarded and yield only new content.
        // Tool events are emitted in real time by AppleBridgedTool via the eventRelay;
        // no post-hoc transcript scan is needed.
        var sentCount = 0
        var fullText = ""
        do {
            for try await partial in response {
                try Task.checkCancellation()
                let text = partial.content
                fullText = text
                let delta = String(text.dropFirst(sentCount))
                if !delta.isEmpty {
                    continuation.yield(.delta(delta))
                    sentCount = text.count
                }
            }
            continuation.yield(.result(fullText, .endTurn))
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // FoundationModels.SystemLanguageModel.tokenCount(for:) and .contextSize
            // ship in the Xcode 26.4 SDK. Use Swift 6.3 as a proxy since Xcode 26.4
            // is the toolchain that vends them.
            #if compiler(>=6.3)
            var contextTokens: Int?
            if #available(macOS 26.4, iOS 26.4, visionOS 26.4, macCatalyst 26.4, *) {
                contextTokens = try? await model.tokenCount(for: languageSession.transcript)
            }
            continuation.finish(throwing: InferenceError.contextWindowExceeded(
                ContextWindowExceededInfo(
                    provider: Self.providerName,
                    message: "Context window exceeded",
                    contextTokens: contextTokens,
                    contextSize: model.contextSize,
                ),
            ))
            #else
            continuation.finish(throwing: InferenceError.contextWindowExceeded(
                ContextWindowExceededInfo(
                    provider: Self.providerName,
                    message: "Context window exceeded",
                ),
            ))
            #endif
        } catch {
            continuation.finish(throwing: error)
        }
    }

    static let providerName = "Apple"

    static func availabilityError() -> InferenceError? {
        guard case .unavailable(let reason) = SystemLanguageModel.default.availability else {
            return nil
        }
        return .providerUnavailable("Apple Intelligence is not available: \(reason)")
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension AppleInferenceSession {
    public func contextUsage() async throws -> ContextUsage {
        let lease = try operationGate.begin(.contextUsage)
        defer {
            lease.end()
        }
        return try await Self.contextUsage(
            for: Array(languageSession.transcript),
            model: model,
        )
    }
}

#endif
