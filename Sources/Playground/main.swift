// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import ArgumentParser
import Darwin
import Foundation

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

// AsyncParsableCommand.main() calls exit() when done; RunLoop keeps the process alive until then.
Task {
    await Playground.main()
    exit(0)
}

RunLoop.main.run()
