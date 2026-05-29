// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

/// A per-model resolution of the context-window size, cached on the session.
enum OpenAIResolvedContextSize {
    case available(Int)
    case unavailable

    var value: Int? {
        switch self {
        case .available(let value):
            value
        case .unavailable:
            nil
        }
    }
}

#endif
