// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Errors thrown by Playground commands.
enum PlaygroundError: LocalizedError, Equatable {
    /// The Apple provider requires macOS 26 or later.
    case appleIntelligenceRequiresMacOS26
    /// The selected provider does not support one or more endpoint options.
    case unsupportedProviderEndpointOptions(provider: String, options: [String])

    var errorDescription: String? {
        switch self {
        case .appleIntelligenceRequiresMacOS26:
            "Apple Intelligence requires macOS 26 or later."
        case .unsupportedProviderEndpointOptions(let provider, let options):
            "\(provider) does not support \(options.joined(separator: ", ")) in Playground."
        }
    }
}
