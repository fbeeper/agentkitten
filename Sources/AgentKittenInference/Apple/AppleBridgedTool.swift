// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
import Foundation
import FoundationModels
import os

private let logger = Logger(subsystem: "AgentKittenCore", category: "AppleBridgedTool")

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
actor AppleToolBridgeRuntime {
    private var activeTurn: ToolTurnRuntime?

    func beginTurn(_ toolTurnRuntime: ToolTurnRuntime) {
        activeTurn = toolTurnRuntime
    }

    func endTurn(_ toolTurnRuntime: ToolTurnRuntime) {
        guard activeTurn === toolTurnRuntime else {
            return
        }
        activeTurn = nil
    }

    func invoke(
        _ call: PendingToolCall,
        toolName: String,
        eventRelay: ToolEventRelay,
    ) async -> ToolCallOutcome {
        guard let activeTurn else {
            logger.error("Tool '\(toolName)' invoked without an active tool turn runtime.")
            return .failure(.execution(
                message: "Tool execution failed because no active Apple inference turn is available.",
            ))
        }
        return await activeTurn.invoke(
            call,
            onApprovalRequired: { pendingCall in
                await eventRelay.emitApprovalRequired(call: pendingCall)
            },
            onHookFired: { info in
                await eventRelay.emitHookFired(info)
            },
        )
    }
}

/// A `FoundationModels.Tool` wrapper around an ``AnyAgentTool``.
///
/// Bridges AgentKitten's type-erased tool abstraction to the native FoundationModels
/// `Tool` protocol so that tools registered with an ``Agent`` are forwarded to
/// `LanguageModelSession` and invoked by the on-device model.
///
/// `Arguments` is `GeneratedContent` — the model's structured output is serialised
/// to JSON via `GeneratedContent.jsonString` and forwarded to the active
/// ``ToolTurnRuntime`` for the current turn.
/// The result is reduced to text and returned as `String`, which FoundationModels treats as
/// `PromptRepresentable` and includes in the next model turn.
///
/// Schema conversion is handled by ``JSONSchemaBridge``. If schema conversion fails at
/// init time the initialiser returns `nil` and an error is logged — the tool is silently
/// skipped rather than crashing the session.
///
/// ## Event emission
/// `call(arguments:)` emits ``InferenceEvent/toolCallRequested`` and
/// ``InferenceEvent/toolCallCompleted(_:_:_:)`` in real time via the shared
/// ``ToolEventRelay``. Outcomes are reported directly; no sentinel encoding is needed.
///
/// ## Error handling
/// `call(arguments:)` never throws. Any error from tool invocation is
/// reported as a ``ToolCallOutcome/failure(_:)`` outcome through the eventRelay, and
/// `{"error":"…"}` is returned to FoundationModels so the model receives a
/// human-readable explanation.
@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
struct AppleBridgedTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema

    private let agentTool: AnyAgentTool
    private let toolBridgeRuntime: AppleToolBridgeRuntime
    private let eventRelay: ToolEventRelay

    /// Creates a bridged tool, or `nil` if schema conversion fails.
    init?(
        agentTool: AnyAgentTool,
        toolBridgeRuntime: AppleToolBridgeRuntime,
        eventRelay: ToolEventRelay,
        rationaleDescription: String,
    ) {
        do {
            self.parameters = try agentTool.schema.toGenerationSchema(
                toolName: agentTool.name,
                rationaleDescription: rationaleDescription,
            )
        } catch {
            logger.error("Schema bridge failed for tool '\(agentTool.name)': \(error)")
            return nil
        }
        self.name = agentTool.name
        self.description = agentTool.description
        self.agentTool = agentTool
        self.toolBridgeRuntime = toolBridgeRuntime
        self.eventRelay = eventRelay
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let callID = UUID().uuidString
        let (rationale, argumentsJSON) = ToolRationale.extracting(from: arguments.jsonString)
        await eventRelay.emitRequested(id: callID, name: agentTool.name, argumentsJSON: argumentsJSON)
        let pendingCall = PendingToolCall(
            id: callID, name: agentTool.name, argumentsJSON: argumentsJSON, modelRationale: rationale,
        )
        let outcome = await toolBridgeRuntime.invoke(
            pendingCall,
            toolName: agentTool.name,
            eventRelay: eventRelay,
        )
        await eventRelay.emitCompleted(
            id: callID,
            name: agentTool.name,
            outcome: outcome,
        )
        switch outcome {
        case .success(let content):
            // Apple validation should make this text-only in practice. If a non-text block
            // slips through during development, drop it rather than aborting the whole turn.
            return content.compactMap { item in
                if case .text(let text) = item {
                    return text
                }
                precondition(
                    !AppleToolResultSupport.supports(item),
                    """
                    AppleBridgedTool received provider-supported non-text output but can only \
                    bridge text to Foundation Models.
                    """,
                )
                return nil
            }.joined(separator: "\n")
        case .failure(let failure):
            if case .execution(let message) = failure {
                logger.error("Tool '\(agentTool.name)' failed: \(message)")
            }
            return failure.resultJSON
        }
    }
}
#endif
