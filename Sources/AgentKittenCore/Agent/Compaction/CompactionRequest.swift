// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

// Internal prompt-building request used between ContextCompactor and SummarizationOptions.
enum CompactionRequest: Sendable {
    case entries([String])
    case summaryAndEntries(summary: String, entries: [String])
}
