// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
import FoundationModels

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension InferenceProvider where Provider == AppleInferenceProvider {
    /// The on-device Apple Intelligence provider.
    ///
    /// Requires Foundation Models support on macOS 26+, iOS 26+, visionOS 26+,
    /// or macCatalyst 26+.
    public static func apple() -> Self {
        Self(AppleInferenceProvider())
    }
}
#endif
