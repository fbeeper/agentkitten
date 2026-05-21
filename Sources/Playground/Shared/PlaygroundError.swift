// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import Foundation

/// Errors thrown by Playground commands.
enum PlaygroundError: LocalizedError, Equatable {
    /// The Apple provider requires macOS 26 or later.
    case appleIntelligenceRequiresMacOS26

    var errorDescription: String? {
        switch self {
        case .appleIntelligenceRequiresMacOS26:
            "Apple Intelligence requires macOS 26 or later."
        }
    }
}
#endif
