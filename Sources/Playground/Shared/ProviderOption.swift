// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import ArgumentParser

/// The inference provider to use for a Playground command.
enum ProviderOption: String, CaseIterable, ExpressibleByArgument {
    case mock
    case apple
    case anthropic
}
