// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
import FoundationModels

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension AppleInferenceSession: ContextCompactableSession {
    public func compactionEntries() -> [RenderedSessionEntry] {
        languageSession.transcript.filter { if case .instructions = $0 { false } else { true } }.map {
            RenderedSessionEntry(isTurnStart: Self.isTurnStarter($0), rendered: Self.render($0))
        }
    }

    public func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int
    ) async throws -> ContextCompactionResult {
        let usageBefore = try await Self.contextUsage(
            for: Array(languageSession.transcript),
            model: model
        )
        let plan = AppleTranscriptCompactionPlan(
            transcript: languageSession.transcript,
            preservedRecentTurnCount: preservedRecentTurnCount
        )
        let entries: [FoundationModels.Transcript.Entry]
        if let summary {
            entries = Self.summaryEntries(summary) + plan.recentEntries
        } else {
            entries = plan.recentEntries
        }
        replaceTranscript(FoundationModels.Transcript(entries: entries))
        let usageAfter = (try? await Self.contextUsage(
            for: Array(languageSession.transcript),
            model: model
        )) ?? usageBefore
        return .compacted(.init(usageBefore: usageBefore, usageAfter: usageAfter))
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension AppleInferenceSession {
    private static func isTurnStarter(_ entry: FoundationModels.Transcript.Entry) -> Bool {
        if case .prompt = entry { return true }
        return false
    }

    static func render(_ entries: [FoundationModels.Transcript.Entry]) -> String {
        entries.compactMap { entry in
            let rendered = render(entry)
            return rendered.isEmpty ? nil : rendered
        }.joined(separator: "\n\n")
    }

    private static func render(_ entry: FoundationModels.Transcript.Entry) -> String {
        let user = AgentKittenInferenceLocalization.string("contextCompaction.userRoleLabel")
        let assistant = AgentKittenInferenceLocalization.string("contextCompaction.assistantRoleLabel")
        switch entry {
        case .instructions:
            return ""
        case .prompt(let prompt):
            return "\(user): \(renderSegments(prompt.segments))"
        case .response(let response):
            return "\(assistant): \(renderSegments(response.segments))"
        case .toolCalls(let toolCalls):
            let calls = toolCalls.map {
                AgentKittenInferenceLocalization.formattedString("contextCompaction.toolCallFormat", $0.toolName)
            }.joined(separator: "\n")
            return "\(assistant): \(calls)"
        case .toolOutput(let output):
            let body = renderSegments(output.segments)
            return AgentKittenInferenceLocalization.formattedString("contextCompaction.toolResultFormat", body)
        @unknown default:
            return entry.description
        }
    }

    private static func renderSegments(_ segments: [FoundationModels.Transcript.Segment]) -> String {
        segments.compactMap { segment -> String? in
            switch segment {
            case .text(let text):
                return text.content
            case .structure(let structured):
                return structured.description
            @unknown default:
                return nil
            }
        }.joined(separator: " ")
    }

    private static func summaryEntries(_ summary: String) -> [FoundationModels.Transcript.Entry] {
        [
            .prompt(.init(segments: [
                .text(.init(content: AgentKittenInferenceLocalization.string("contextCompaction.summaryMarker"))),
            ])),
            .response(.init(assetIDs: [], segments: [
                .text(.init(content: summary)),
            ])),
        ]
    }

    static func contextUsage(
        for entries: [FoundationModels.Transcript.Entry],
        model: SystemLanguageModel
    ) async throws -> ContextUsage {
        guard #available(macOS 26.4, iOS 26.4, visionOS 26.4, macCatalyst 26.4, *) else {
            throw InferenceError.unsupportedConfiguration(
                "Apple context usage requires FoundationModels token counting on OS 26.4 or newer."
            )
        }
        // FoundationModels.SystemLanguageModel.contextSize ships in the
        // Xcode 26.4 SDK. Use Swift 6.3 as a proxy since Xcode 26.4 is
        // the toolchain that vends it.
        #if compiler(>=6.3)
        return ContextUsage(
            contextTokens: try await model.tokenCount(for: entries),
            contextSize: model.contextSize
        )
        #else
        throw InferenceError.unsupportedConfiguration(
            "Apple context usage requires the Xcode 26.4 SDK (Swift 6.3) or newer."
        )
        #endif
    }
}
#endif
