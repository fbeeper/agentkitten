// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct AgentKittenMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        ToolMacro.self,
        ParameterDescriptionMacro.self,
    ]
}
