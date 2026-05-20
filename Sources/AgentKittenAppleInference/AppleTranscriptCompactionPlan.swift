// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
struct AppleTranscriptCompactionPlan {
    let summarizedEntries: [FoundationModels.Transcript.Entry]
    let recentEntries: [FoundationModels.Transcript.Entry]

    init(
        transcript: FoundationModels.Transcript,
        preservedRecentTurnCount: Int,
    ) {
        let entries = Array(transcript)
        let nonInstructions = entries.filter { entry in
            if case .instructions = entry {
                return false
            }
            return true
        }
        let recentStart = Self.recentStartIndex(
            in: nonInstructions,
            preservedRecentTurnCount: max(0, preservedRecentTurnCount),
        )
        let oldEntries = Array(nonInstructions[..<recentStart])
        recentEntries = Array(nonInstructions[recentStart...])
        summarizedEntries = oldEntries
    }

    private static func recentStartIndex(
        in entries: [FoundationModels.Transcript.Entry],
        preservedRecentTurnCount: Int,
    ) -> Int {
        guard preservedRecentTurnCount > 0 else {
            return entries.endIndex
        }

        var promptsSeen = 0
        for index in entries.indices.reversed() {
            if case .prompt = entries[index] {
                promptsSeen += 1
                if promptsSeen == preservedRecentTurnCount {
                    return index
                }
            }
        }
        return entries.startIndex
    }
}
#endif
