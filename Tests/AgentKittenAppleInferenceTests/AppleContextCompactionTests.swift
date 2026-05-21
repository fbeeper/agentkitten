// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenAppleInference
import AgentKittenCore
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
    guard case .available = SystemLanguageModel.default.availability else {
        return
    }

    let transcript = FoundationModels.Transcript(entries: [
        .instructions(FoundationModels.Transcript.Instructions(segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "System instructions.")),
        ], toolDefinitions: [])),
        .prompt(FoundationModels.Transcript.Prompt(segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Old user request.")),
        ])),
        .response(FoundationModels.Transcript.Response(assetIDs: [], segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Old assistant answer.")),
        ])),
        .prompt(FoundationModels.Transcript.Prompt(segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Recent user request one.")),
        ])),
        .response(FoundationModels.Transcript.Response(assetIDs: [], segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Recent assistant answer one.")),
        ])),
        .prompt(FoundationModels.Transcript.Prompt(segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Recent user request two.")),
        ])),
        .response(FoundationModels.Transcript.Response(assetIDs: [], segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Recent assistant answer two.")),
        ])),
    ])

    let session = AppleInferenceSession(
        transcript: transcript,
        model: SystemLanguageModel.default,
        toolRuntime: testToolRuntime(),
        toolSelection: .all,
    )

    let result = await ContextCompactor().compact(
        session,
        options: .summarize(ContextCompactionOptions.SummarizationOptions(preservedRecentTurnCount: 2)),
        summaryGenerator: makeSummaryGenerator(model: session.model),
    )
    guard result.didCompact else { return }

    let compacted = await session.captureTranscript()
    let descriptions = Array(compacted).map(\.description).joined(separator: "\n")

    #expect(Array(compacted).count == 6)
    #expect(!descriptions.contains("System instructions."))
    #expect(descriptions.contains("[Conversation summary]"))
    #expect(descriptions.contains("Recent user request one."))
    #expect(descriptions.contains("Recent user request two."))
}

#if compiler(>=6.3)
@available(macOS 26.4, iOS 26.4, visionOS 26.4, macCatalyst 26.4, *)
@Test func appleCompactedTranscript_truncatesOldEntriesWithoutSummarizing() async {
    let transcript = FoundationModels.Transcript(entries: [
        .instructions(FoundationModels.Transcript.Instructions(segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "System instructions.")),
        ], toolDefinitions: [])),
        .prompt(FoundationModels.Transcript.Prompt(segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Old user request.")),
        ])),
        .response(FoundationModels.Transcript.Response(assetIDs: [], segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Old assistant answer.")),
        ])),
        .prompt(FoundationModels.Transcript.Prompt(segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Recent user request.")),
        ])),
        .response(FoundationModels.Transcript.Response(assetIDs: [], segments: [
            .text(FoundationModels.Transcript.TextSegment(content: "Recent assistant answer.")),
        ])),
    ])

    let session = AppleInferenceSession(
        transcript: transcript,
        model: SystemLanguageModel.default,
        toolRuntime: testToolRuntime(),
        toolSelection: .all,
    )

    let result = await ContextCompactor().compact(
        session,
        options: .truncate(ContextCompactionOptions.TruncationOptions(preservedRecentTurnCount: 1)),
        summaryGenerator: makeSummaryGenerator(model: session.model),
    )
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
#endif
