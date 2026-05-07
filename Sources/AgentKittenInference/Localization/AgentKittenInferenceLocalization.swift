// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization
import AgentKittenCore

/// Localization lookup for model-facing strings owned by AgentKittenInference.
///
/// Resolves against the AgentKittenInference bundle. Set ``overrideBundle`` to
/// substitute inference strings independently of core strings. Both modules
/// share ``AgentKittenLocalization/overrideLocale`` as the single locale setting.
public enum AgentKittenInferenceLocalization {
    private static let packagedBundle = Bundle.module

    private static let state = Mutex(State())

    private struct State: Sendable {
        var overrideBundle: Bundle?
    }

    /// A replacement bundle for AgentKittenInference strings, consulted before the packaged catalog.
    ///
    /// Set once at startup to supply custom inference model-facing strings. Keys missing from
    /// the override bundle trigger an assertion and fall through to the packaged catalog.
    public static var overrideBundle: Bundle? {
        get { state.withLock { $0.overrideBundle } }
        set { state.withLock { $0.overrideBundle = newValue } }
    }

    static func string(_ key: String) -> String {
        let overrideBundle = state.withLock { $0.overrideBundle }
        return AgentKittenLocalization.resolve(key, overrideBundle: overrideBundle, packagedBundle: packagedBundle)
    }

    static func formattedString(_ key: String, _ arguments: CVarArg...) -> String {
        let overrideBundle = state.withLock { $0.overrideBundle }
        return AgentKittenLocalization.resolveFormatted(
            key,
            overrideBundle: overrideBundle,
            packagedBundle: packagedBundle,
            arguments: arguments
        )
    }
}
