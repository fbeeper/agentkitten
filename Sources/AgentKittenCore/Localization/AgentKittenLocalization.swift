// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization

/// Central lookup for all model-facing strings owned by AgentKitten.
///
/// Clients may substitute strings by setting ``overrideBundle`` before their first
/// agent operation. Override bundles are consulted first; keys absent from the override
/// bundle trigger an assertion and fall through to the packaged English catalog.
public enum AgentKittenLocalization {
    private static let packagedBundle = Bundle.module

    private static let state = Mutex(State())

    private struct State: Sendable {
        var overrideBundle: Bundle?
        var overrideLocale: Locale?
    }

    /// A replacement bundle for AgentKittenCore strings, consulted before the packaged catalog.
    ///
    /// Set once at startup to supply custom core model-facing strings. Keys missing from
    /// the override bundle trigger an assertion and fall through to the packaged catalog.
    public static var overrideBundle: Bundle? {
        get { state.withLock { $0.overrideBundle } }
        set { state.withLock { $0.overrideBundle = newValue } }
    }

    /// Locale used for all ``formattedString(_:_:)`` calls across AgentKitten.
    /// Defaults to ``Locale/current`` when `nil`.
    public static var overrideLocale: Locale? {
        get { state.withLock { $0.overrideLocale } }
        set { state.withLock { $0.overrideLocale = newValue } }
    }

    /// Returns the localized string for `key`.
    ///
    /// Lookup order: override bundle (if set), then packaged English catalog.
    /// An absent key in the override bundle triggers `assertionFailure` and falls through.
    /// An absent key in the packaged catalog is a `preconditionFailure`.
    static func string(_ key: String) -> String {
        let overrideBundle = state.withLock { $0.overrideBundle }
        return resolve(key, overrideBundle: overrideBundle, packagedBundle: packagedBundle)
    }

    /// Returns the localized format string for `key` filled with `arguments`.
    ///
    /// When resolving from the override bundle, uses ``overrideLocale`` or ``Locale/current``.
    /// When falling back to the packaged catalog, uses the English locale.
    static func formattedString(_ key: String, _ arguments: CVarArg...) -> String {
        let overrideBundle = state.withLock { $0.overrideBundle }
        return resolveFormatted(
            key,
            overrideBundle: overrideBundle,
            packagedBundle: packagedBundle,
            arguments: arguments
        )
    }

    // MARK: Package-level shared resolution

    package static func resolve(_ key: String, overrideBundle: Bundle?, packagedBundle: Bundle) -> String {
        if let overrideBundle {
            if let value = lookup(key, in: overrideBundle) {
                return value
            }
            assertionFailure("AgentKittenLocalization: override bundle is missing key '\(key)'.")
        }
        guard let value = lookup(key, in: packagedBundle) else {
            preconditionFailure("AgentKittenLocalization: missing key '\(key)' from packaged catalog.")
        }
        return value
    }

    package static func resolveFormatted(
        _ key: String,
        overrideBundle: Bundle?,
        packagedBundle: Bundle,
        arguments: [CVarArg]
    ) -> String {
        let overrideLocale = state.withLock { $0.overrideLocale }
        if let overrideBundle {
            if let value = lookup(key, in: overrideBundle) {
                return String(format: value, locale: overrideLocale ?? .current, arguments: arguments)
            }
            assertionFailure("AgentKittenLocalization: override bundle is missing key '\(key)'.")
        }
        guard let template = lookup(key, in: packagedBundle) else {
            preconditionFailure("AgentKittenLocalization: missing key '\(key)' from packaged catalog.")
        }
        return String(format: template, locale: Locale(identifier: "en"), arguments: arguments)
    }

    // MARK: Private

    private static let missingSentinel = "\u{FEFF}AgentKitten_MISSING"

    private static func lookup(_ key: String, in bundle: Bundle) -> String? {
        let value = bundle.localizedString(forKey: key, value: missingSentinel, table: "AgentKitten")
        return value == missingSentinel ? nil : value
    }
}
