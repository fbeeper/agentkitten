// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore

extension AnthropicInferenceSession {
    func apiKey() async throws -> String {
        try await credentials.apiKey()
    }
}
#endif
