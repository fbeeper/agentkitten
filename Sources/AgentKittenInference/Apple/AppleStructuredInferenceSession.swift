// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
import Foundation
import FoundationModels

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension AppleInferenceSession: StructuredInferenceSession {
    public func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters
    ) async throws
        -> StructuredInferenceStream<T> {
        let lease = try operationGate.begin(.generate)
        let toolTurnRuntime = toolRuntime.makeTurnRuntime(
            toolStepBudget: parameters.toolStepBudget,
            context: parameters.toolExecutionContext,
            toolSelection: parameters.toolSelection
        )
        await toolBridgeRuntime.beginTurn(toolTurnRuntime)
        do {
            let schema = try makeStructuredSchema(T.self)
            let toolBridgeRuntime = self.toolBridgeRuntime
            return AsyncThrowingStream { continuation in
                let task = Task {
                    let relayTurn = await eventRelay.beginTurn(continuation)
                    defer {
                        Task { await eventRelay.endTurn(relayTurn) }
                        Task { await toolBridgeRuntime.endTurn(toolTurnRuntime) }
                    }
                    do {
                        let jsonString = try await respondStructured(prompt: prompt, schema: schema)
                        let value = try decodeStructuredValue(T.self, from: jsonString)
                        continuation.yield(.result(value, .endTurn))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    lease.end()
                    task.cancel()
                    Task { await self.toolBridgeRuntime.endTurn(toolTurnRuntime) }
                }
            }
        } catch {
            lease.end()
            await toolBridgeRuntime.endTurn(toolTurnRuntime)
            throw error
        }
    }

    private func makeStructuredSchema<T: JSONSchemaProviding>(
        _ type: T.Type
    ) throws -> GenerationSchema {
        if let error = Self.availabilityError() {
            throw error
        }
        do {
            let root = T.jsonSchema.toDynamicSchema(name: "Output")
            return try GenerationSchema(root: root, dependencies: [])
        } catch {
            throw StructuredGenerationError.generationFailed(error)
        }
    }

    private func respondStructured(
        prompt: String,
        schema: GenerationSchema
    ) async throws -> String {
        let response = try await languageSession.respond(
            to: Prompt(prompt),
            schema: schema,
            includeSchemaInPrompt: true
        )
        return response.content.jsonString
    }

    private func decodeStructuredValue<T: Decodable>(
        _ type: T.Type,
        from json: String
    ) throws(StructuredGenerationError) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw StructuredGenerationError.decodingFailed(error)
        }
    }
}
#endif
