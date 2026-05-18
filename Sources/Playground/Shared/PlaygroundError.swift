// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Errors thrown by Playground commands.
enum PlaygroundError: LocalizedError, Equatable {
    /// The Apple provider requires macOS 26 or later.
    case appleIntelligenceRequiresMacOS26
    /// The Apple provider requires FoundationModels (Apple platforms only).
    case appleIntelligenceNeedsFoundationModels

    var errorDescription: String? {
        switch self {
        case .appleIntelligenceRequiresMacOS26:
            "Apple Intelligence requires macOS 26 or later."
        case .appleIntelligenceNeedsFoundationModels:
            "Apple Intelligence requires FoundationModels (Apple platforms only)."
        }
    }
}
