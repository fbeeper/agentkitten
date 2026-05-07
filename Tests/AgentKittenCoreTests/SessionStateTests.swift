// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

@Suite("Session State")
struct SessionStateTests {
    @Test func readOnlyState_rejectsDirectMutation() async throws {
        let trace = AgentTrace(retentionPolicy: .maxTurns(10))
        let state = SessionState.readOnly(
            trace: trace,
            contents: ["topic": "Swift"]
        )

        #expect(await state.value(forKey: "topic") == "Swift")
        await #expect(throws: SessionStateError.readOnlyMutation) {
            try await state.setValue("Rust", forKey: "topic")
        }
        await #expect(throws: SessionStateError.readOnlyMutation) {
            _ = try await state.removeValue(forKey: "topic")
        }
        await #expect(throws: SessionStateError.readOnlyMutation) {
            _ = try await state.clear()
        }
        #expect(await state.value(forKey: "topic") == "Swift")
    }

    @Test func clear_removesAllValues() async throws {
        let trace = AgentTrace(retentionPolicy: .maxTurns(10))
        let state = SessionState(
            trace: trace,
            contents: [
                "language": "Swift",
                "topic": "Agents",
            ]
        )

        let removedKeys = try await state.clear()

        #expect(removedKeys == ["language", "topic"])
        #expect(await state.contents().isEmpty)
    }

    @Test func disabledStateToolsRemainUnavailable() async throws {
        let provider = ScriptedInferenceProvider(responses: [
            .toolCall(
                name: "get_state",
                argumentsJSON: #"{"key":"topic"}"#,
                thenRespond: "No state available."
            ),
        ])
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
        )
        let session = agent.makeSession()

        let turn = try await session.send("Read scratchpad")
        _ = try await collectEvents(from: turn)

        let entries = await directTurnEntries(for: turn.id, on: session)
        let result = try requireToolResult(named: "get_state", in: entries)
        #expect(result.name == "get_state")
        #expect(result.isError)
        let resultText = try #require(singleTextSummary(in: result))
        #expect(resultText.contains("toolNotFound"))
        #expect(resultText.contains("get_state"))
        #expect(
            !entries.contains {
                if case .stateMutation = $0.kind {
                    return true
                }
                return false
            }
        )
    }

    @Test func enabledStateToolsPersistAcrossTurnsWithinSession() async throws {
        let provider = ScriptedInferenceProvider(responses: [
            .toolCall(
                name: "set_state",
                argumentsJSON: #"{"key":"topic","value":"Swift"}"#,
                thenRespond: "Saved."
            ),
            .toolCall(
                name: "get_state",
                argumentsJSON: #"{"key":"topic"}"#,
                thenRespond: "Loaded."
            ),
        ])
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test("Base prompt"),
            sessionState: .enabledWithDefaultGuidance
        )
        let session = agent.makeSession()

        let firstTurn = try await session.send("Remember the topic")
        _ = try await collectEvents(from: firstTurn)
        let secondTurn = try await session.send("Read the topic")
        _ = try await collectEvents(from: secondTurn)

        let storedValue = await session.state.value(forKey: "topic")
        #expect(storedValue == "Swift")

        let firstEntries = await directTurnEntries(for: firstTurn.id, on: session)
        let mutationEntry = try #require(firstEntries.first { entry in
            if case .stateMutation = entry.kind {
                return true
            }
            return false
        })
        guard case .stateMutation(let mutation) = mutationEntry.kind else {
            Issue.record("Expected state mutation trace entry after set_state")
            return
        }
        #expect(mutation.operation == .set)
        #expect(mutation.key == "topic")
        #expect(mutation.valueType == "string")

        let secondEntries = await directTurnEntries(for: secondTurn.id, on: session)
        let result = try requireToolResult(named: "get_state", in: secondEntries)
        #expect(result.isError == false)
        #expect(try #require(singleTextSummary(in: result)).contains(#""value":"Swift""#))

        let latestPrompt = await provider.script.latestPrompt()
        #expect(latestPrompt?.contains(SessionStateConfiguration.defaultPromptGuidance) == true)
    }

    @Test func defaultSessionStateGuidance_discouragesGenericBookkeeping() {
        let guidance = SessionStateConfiguration.defaultPromptGuidance.localizedLowercase

        #expect(guidance.contains("do not create generic bookkeeping entries"))
        #expect(guidance.contains("do not store plan outlines"))
        #expect(guidance.contains("goal restatements"))
        #expect(guidance.contains("final answers"))
        #expect(guidance.contains("fewest state reads and writes"))
    }

    @Test func readOnlyStateToolsExposeReadsAndOmitWrites() async throws {
        let provider = ScriptedInferenceProvider(responses: [
            .toolCall(
                name: "list_state_keys",
                argumentsJSON: "{}",
                thenRespond: "Listed."
            ),
            .toolCall(
                name: "set_state",
                argumentsJSON: #"{"key":"topic","value":"Swift"}"#,
                thenRespond: "Attempted."
            ),
        ])
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
            sessionState: .readOnlyWithDefaultGuidance
        )
        let session = agent.makeSession()

        let readTurn = try await session.send("List scratchpad keys")
        _ = try await collectEvents(from: readTurn)
        let writeTurn = try await session.send("Try to write")
        _ = try await collectEvents(from: writeTurn)

        #expect(await session.state.value(forKey: "topic") == nil)
        let readEntries = await directTurnEntries(for: readTurn.id, on: session)
        let readResult = try requireToolResult(named: "list_state_keys", in: readEntries)
        #expect(readResult.isError == false)
        #expect(try #require(singleTextSummary(in: readResult)).contains(#""keys":[]"#))

        let writeEntries = await directTurnEntries(for: writeTurn.id, on: session)
        let writeResult = try requireToolResult(named: "set_state", in: writeEntries)
        #expect(writeResult.isError)
        let resultText = try #require(singleTextSummary(in: writeResult))
        #expect(resultText.contains("toolNotFound"))
        #expect(resultText.contains("set_state"))
        #expect(
            !writeEntries.contains {
                if case .stateMutation = $0.kind {
                    return true
                }
                return false
            }
        )

        let latestPrompt = await provider.script.latestPrompt()
        #expect(
            latestPrompt?.contains("Session state is read-only in this session.") == true
        )
    }

    @Test func stateDoesNotLeakAcrossSessions() async throws {
        let provider = ScriptedInferenceProvider(responses: [
            .toolCall(
                name: "set_state",
                argumentsJSON: #"{"key":"topic","value":"Swift"}"#,
                thenRespond: "Saved."
            ),
            .toolCall(
                name: "get_state",
                argumentsJSON: #"{"key":"topic"}"#,
                thenRespond: "Missing."
            ),
        ])
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
            sessionState: .enabledWithDefaultGuidance
        )
        let firstSession = agent.makeSession()
        let secondSession = agent.makeSession()

        let firstTurn = try await firstSession.send("Save")
        _ = try await collectEvents(from: firstTurn)
        let secondTurn = try await secondSession.send("Read")
        _ = try await collectEvents(from: secondTurn)

        #expect(await firstSession.state.value(forKey: "topic") == "Swift")
        #expect(await secondSession.state.value(forKey: "topic") == nil)

        let secondEntries = await directTurnEntries(for: secondTurn.id, on: secondSession)
        let result = try requireToolResult(named: "get_state", in: secondEntries)
        let resultText = try #require(singleTextSummary(in: result))
        let resultObject = try #require(jsonObject(from: resultText))
        #expect(resultObject.isEmpty)
    }

    @Test func setStateAcceptsPlainTextWithoutJSONStringEscaping() async throws {
        let provider = ScriptedInferenceProvider(responses: [
            .toolCall(
                name: "set_state",
                argumentsJSON: #"{"key":"tone","value":"concise"}"#,
                thenRespond: "Saved."
            ),
        ])
        let agent = Agent(
            providerRegistry: ProviderRegistry(default: provider),
            behavior: .test(),
            sessionState: .enabledWithDefaultGuidance
        )
        let session = agent.makeSession()

        let turn = try await session.send("Remember tone")
        _ = try await collectEvents(from: turn)

        #expect(await session.state.value(forKey: "tone") == "concise")
    }

    private func requireToolResult(
        named name: String,
        in entries: [AgentTraceEntry]
    ) throws -> ToolResultMessage {
        let entry = try #require(entries.first { entry in
            guard case .message(.toolResult(let result)) = entry.kind else {
                return false
            }
            return result.name == name
        })
        guard case .message(.toolResult(let result)) = entry.kind else {
            Issue.record("Expected tool result trace entry for \(name)")
            throw SessionStateTestError.expectedToolResultMissing
        }
        return result
    }

    private func jsonObject(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

}

private enum SessionStateTestError: Error {
    case expectedToolResultMissing
}
