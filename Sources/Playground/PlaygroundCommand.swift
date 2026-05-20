// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import ArgumentParser

@main
struct Playground: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "AgentKitten development playground.",
        subcommands: [
            Generate.self,
            Chat.self, Tools.self,
            Classify.self,
            Chicken.self,
            PII.self,
            PlanMode.self,
        ],
    )
}
