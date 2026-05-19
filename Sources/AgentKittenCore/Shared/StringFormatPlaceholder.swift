// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension String {
    /// Number of `%@`-family format placeholders in the string.
    ///
    /// Matches both plain `%@` and positional variants such as `%1$@`, `%2$@`.
    package var formatPlaceholderCount: Int {
        matches(of: /%(\d+\$)?@/).count
    }
}
