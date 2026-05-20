// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Security)
import Foundation
import Security

/// Reads an API key from the system Keychain.
///
/// Recommended for app targets where storing secrets in environment variables
/// is not appropriate.
///
/// ```swift
/// let credentials = KeychainAPIKeyProvider(service: "com.example.MyApp", account: "anthropic")
/// let provider = InferenceProvider.anthropic(credentials: credentials)
/// ```
///
/// The Keychain read executes synchronously (via `SecItemCopyMatching`) and
/// completes in microseconds. The async interface satisfies ``APIKeyProviding``
/// without meaningful overhead.
public struct KeychainAPIKeyProvider: APIKeyProviding {
    private let service: String
    private let account: String

    /// Creates a provider for the given Keychain service and account.
    ///
    /// - Parameters:
    ///   - service: Keychain service name (typically the app's bundle ID).
    ///   - account: Keychain account name distinguishing multiple keys under the same service.
    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public func apiKey() async throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw APIKeyError.missing(
                    "Keychain item not found (service: \(service), account: \(account)).",
                )
            }
            throw APIKeyError.underlyingError(
                "Keychain read failed (service: \(service), account: \(account)).",
                NSError(domain: NSOSStatusErrorDomain, code: Int(status)),
            )
        }
        guard
            let data = result as? Data,
            let key = String(data: data, encoding: .utf8),
            !key.isEmpty
        else {
            throw APIKeyError.invalidData(
                "Keychain data for (service: \(service), account: \(account)) is not valid UTF-8.",
            )
        }
        return key
    }
}
#endif
