// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore

func testToolRuntime(
    registry: ToolRegistry = ToolRegistry(),
    executionPolicy: some ToolExecutionPolicy = AutoApprovePolicy(),
) -> ToolRuntime {
    let toolBehavior = ToolBehavior()
    return ToolRuntime(
        toolDefinition: ToolDefinition(
            tools: registry.all,
            executionPolicy: executionPolicy,
        ),
        toolBehavior: toolBehavior,
    )
}
