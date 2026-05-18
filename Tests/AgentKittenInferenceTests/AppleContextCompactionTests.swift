// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
@testable import AgentKittenInference
import Testing

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
private func makeSummaryGenerator(model: SystemLanguageModel) -> @Sendable (String) async throws -> String {
    { @Sendable prompt in
        let ephemeral = AppleInferenceSession(
            systemPrompt: nil,
            model: model,
            toolRuntime: testToolRuntime(),
            toolSelection: .disabled,
        )
        let stream = try await ephemeral.run(
            UserMessage(text: prompt),
            parameters: InferenceRequestParameters(toolSelection: .disabled),
        )
        for try await event in stream {
            if case .result(let text, _) = event {
                return text
            }
        }
        throw InferenceError.invalidResponse("Summarization produced no result.")
    }
}

@available(macOS 26.4, iOS 26.4, visionOS 26.4, macCatalyst 26.4, *)
@Test func appleCompactedTranscript_excludesInstructionsAndSummarizesOlderTurns() async {
    let transcript = FoundationModels.Transcript(entries: [
        .instructions(.init(segments: [.text(.init(content: "System instructions."))], toolDefinitions: [])),
        .prompt(.init(segments: [.text(.init(content: "Old user request."))])),
        .response(.init(assetIDs: [], segments: [.text(.init(content: "Old assistant answer."))])),
        .prompt(.init(segments: [.text(.init(content: "Recent user request one."))])),
        .response(.init(assetIDs: [], segments: [.text(.init(content: "Recent assistant answer one."))])),
        .prompt(.init(segments: [.text(.init(content: "Recent user request two."))])),
        .response(.init(assetIDs: [], segments: [.text(.init(content: "Recent assistant answer two."))])),
    ])

    let session = AppleInferenceSession(
        transcript: transcript,
        model: SystemLanguageModel.default,
        toolRuntime: testToolRuntime(),
        toolSelection: .all,
    )

    let result = await ContextCompactor().compact(session,
                                                  options: .summarize(.init(preservedRecentTurnCount: 2)),
                                                  summaryGenerator: makeSummaryGenerator(model: session.model))
    #expect(result.didCompact)

    let compacted = await session.captureTranscript()
    let descriptions = Array(compacted).map(\.description).joined(separator: "\n")

    #expect(Array(compacted).count == 6)
    #expect(!descriptions.contains("System instructions."))
    #expect(descriptions.contains("[Conversation summary]"))
    #expect(descriptions.contains("Recent user request one."))
    #expect(descriptions.contains("Recent user request two."))
}

@available(macOS 26.4, iOS 26.4, visionOS 26.4, macCatalyst 26.4, *)
@Test func appleCompactedTranscript_truncatesOldEntriesWithoutSummarizing() async {
    let transcript = FoundationModels.Transcript(entries: [
        .instructions(.init(segments: [.text(.init(content: "System instructions."))], toolDefinitions: [])),
        .prompt(.init(segments: [.text(.init(content: "Old user request."))])),
        .response(.init(assetIDs: [], segments: [.text(.init(content: "Old assistant answer."))])),
        .prompt(.init(segments: [.text(.init(content: "Recent user request."))])),
        .response(.init(assetIDs: [], segments: [.text(.init(content: "Recent assistant answer."))])),
    ])

    let session = AppleInferenceSession(
        transcript: transcript,
        model: SystemLanguageModel.default,
        toolRuntime: testToolRuntime(),
        toolSelection: .all,
    )

    let result = await ContextCompactor().compact(session,
                                                  options: .truncate(.init(preservedRecentTurnCount: 1)),
                                                  summaryGenerator: makeSummaryGenerator(model: session.model))
    #expect(result.didCompact)

    let compacted = await session.captureTranscript()
    let descriptions = Array(compacted).map(\.description).joined(separator: "\n")

    #expect(Array(compacted).count == 2)
    #expect(descriptions.contains("Recent user request."))
    #expect(descriptions.contains("Recent assistant answer."))
    #expect(!descriptions.contains("Old user request."))
    #expect(!descriptions.contains("Old assistant answer."))
}
#endif
