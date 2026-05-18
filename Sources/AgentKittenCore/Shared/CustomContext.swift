// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

struct CustomContext: Sendable, Equatable, Hashable {
    private var customValues: [String: ExecutionConfigurationCustomValue]

    init() {
        customValues = [:]
    }

    init(customValues: [String: ExecutionConfigurationCustomValue]) {
        self.customValues = customValues
    }

    subscript<Key: ExecutionConfigurationKey>(_ key: Key.Type) -> Key.Value? {
        get {
            customValues[Key.id]?.value as? Key.Value
        }
        set {
            if let newValue {
                customValues[Key.id] = ExecutionConfigurationCustomValue(
                    domains: Key.domains,
                    value: newValue,
                )
            } else {
                customValues.removeValue(forKey: Key.id)
            }
        }
    }

    var traceSnapshot: CustomContextSnapshot? {
        let entries = customValues
            .map { key, value in
                CustomContextSnapshot.Entry(
                    key: key,
                    valueSummary: String(describing: value.value),
                )
            }
            .sorted { $0.key < $1.key }
        guard !entries.isEmpty else {
            return nil
        }
        return CustomContextSnapshot(entries: entries)
    }
}
