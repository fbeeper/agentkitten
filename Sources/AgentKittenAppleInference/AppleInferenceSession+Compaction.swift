// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
import FoundationModels

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension AppleInferenceSession: ContextCompactableSession {
    public func compactionEntries() -> [RenderedSessionEntry] {
        languageSession.transcript.filter { if case .instructions = $0 { false } else { true } }.map {
            RenderedSessionEntry(isTurnStart: Self.isTurnStarter($0), rendered: render($0))
        }
    }

    public func applyCompaction(
        summary: String?,
        preservedRecentTurnCount: Int,
    ) async throws -> ContextCompactionResult {
        let usageBefore = try await Self.contextUsage(
            for: Array(languageSession.transcript),
            model: model,
        )
        let compactableEntries = Self.compactableEntries(from: languageSession.transcript)
        let plan = TurnPreservationPlan(
            entries: compactableEntries,
            preservedRecentTurnCount: preservedRecentTurnCount,
            isTurnStart: Self.isTurnStarter,
        )
        let entries: [FoundationModels.Transcript.Entry] = if let summary {
            summaryEntries(summary) + plan.recentEntries(from: compactableEntries)
        } else {
            plan.recentEntries(from: compactableEntries)
        }
        replaceTranscript(FoundationModels.Transcript(entries: entries))
        let usageAfter = (try? await Self.contextUsage(
            for: Array(languageSession.transcript),
            model: model,
        )) ?? usageBefore
        return .compacted(
            ContextCompactionResult.Compacted(
                usageBefore: usageBefore,
                usageAfter: usageAfter,
            ),
        )
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension AppleInferenceSession {
    static func compactableEntries(
        from transcript: FoundationModels.Transcript,
    ) -> [FoundationModels.Transcript.Entry] {
        Array(transcript).filter {
            if case .instructions = $0 { false } else { true }
        }
    }

    private static func isTurnStarter(_ entry: FoundationModels.Transcript.Entry) -> Bool {
        if case .prompt = entry { return true }
        return false
    }

    func render(_ entries: [FoundationModels.Transcript.Entry]) -> String {
        entries.compactMap { entry in
            let rendered = render(entry)
            return rendered.isEmpty ? nil : rendered
        }.joined(separator: "\n\n")
    }

    private func render(_ entry: FoundationModels.Transcript.Entry) -> String {
        switch entry {
        case .instructions:
            return ""
        case .prompt(let prompt):
            return "\(historyRenderingConfiguration.userRoleLabel): \(Self.renderSegments(prompt.segments))"
        case .response(let response):
            return "\(historyRenderingConfiguration.assistantRoleLabel): \(Self.renderSegments(response.segments))"
        case .toolCalls(let toolCalls):
            let calls = toolCalls.map {
                String(format: historyRenderingConfiguration.toolCallFormat, $0.toolName)
            }.joined(separator: "\n")
            return "\(historyRenderingConfiguration.assistantRoleLabel): \(calls)"
        case .toolOutput(let output):
            let body = Self.renderSegments(output.segments)
            return String(format: historyRenderingConfiguration.toolResultFormat, body)
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

    private func summaryEntries(_ summary: String) -> [FoundationModels.Transcript.Entry] {
        [
            .prompt(FoundationModels.Transcript.Prompt(segments: [
                .text(FoundationModels.Transcript.TextSegment(content: historyRenderingConfiguration.summaryMarker)),
            ])),
            .response(FoundationModels.Transcript.Response(assetIDs: [], segments: [
                .text(FoundationModels.Transcript.TextSegment(content: summary)),
            ])),
        ]
    }

    static func contextUsage(
        for entries: [FoundationModels.Transcript.Entry],
        model: SystemLanguageModel,
    ) async throws -> ContextUsage {
        guard #available(macOS 26.4, iOS 26.4, visionOS 26.4, macCatalyst 26.4, *) else {
            throw InferenceError.unsupportedConfiguration(
                "Apple context usage requires FoundationModels token counting on OS 26.4 or newer.",
            )
        }
        // FoundationModels.SystemLanguageModel.contextSize ships in the
        // Xcode 26.4 SDK. Use Swift 6.3 as a proxy since Xcode 26.4 is
        // the toolchain that vends it.
        #if compiler(>=6.3)
        return ContextUsage(
            contextTokens: .tokens(UInt(try await model.tokenCount(for: entries))),
            contextSize: TokenCount(model.contextSize),
        )
        #else
        throw InferenceError.unsupportedConfiguration(
            "Apple context usage requires the Xcode 26.4 SDK (Swift 6.3) or newer.",
        )
        #endif
    }
}
#endif
