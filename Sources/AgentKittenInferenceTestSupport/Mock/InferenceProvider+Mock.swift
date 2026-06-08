// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

extension InferenceProvider where Provider == MockInferenceProvider {
    /// A mock provider that returns canned responses.
    ///
    /// Useful in tests, previews, and platforms where on-device models are unavailable.
    public static func mock() -> Self {
        Self(MockInferenceProvider())
    }
}
