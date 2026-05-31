// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenInferenceSupport

public enum OpenAICredentials: Sendable {
    case key(any APIKeyProviding)
    case noCredential
}
#endif
