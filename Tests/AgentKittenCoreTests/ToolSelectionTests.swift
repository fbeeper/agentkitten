// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

@Test func toolSelection_allowsExpectedToolNames() {
    #expect(ToolSelection.all.allows(toolName: "echo"))
    #expect(!ToolSelection.disabled.allows(toolName: "echo"))
    #expect(ToolSelection.including(["echo", "weather"]).allows(toolName: "echo"))
    #expect(!ToolSelection.including(["weather"]).allows(toolName: "echo"))
    #expect(!ToolSelection.excluding(["echo"]).allows(toolName: "echo"))
    #expect(ToolSelection.excluding(["weather"]).allows(toolName: "echo"))
}

@Test func toolSelectionSnapshot_codableRoundTrips() throws {
    typealias Snapshot = ToolSelectionSnapshot
    let cases: [Snapshot] = [
        .all,
        .disabled,
        .including(["echo", "weather"]),
        .excluding(["echo", "write_file"]),
    ]
    for selection in cases {
        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
        #expect(decoded == selection)
    }
}

@Test func toolSelection_snapshotSortsNames() {
    #expect(ToolSelection.including(["weather", "echo"]).traceSnapshot == .including(["echo", "weather"]))
    #expect(ToolSelection.excluding(["write_file", "echo"]).traceSnapshot == .excluding(["echo", "write_file"]))
}

@Test func toolRegistry_filtersToolsBySelection() async {
    let registry = ToolRegistry([
        AnyAgentTool(CountingEchoTool(counter: ToolCallCounter())),
        AnyAgentTool(SelectionOtherTool()),
    ])

    #expect(Set(registry.tools(matching: .including(["counting_echo"])).map(\.name)) == ["counting_echo"])
    #expect(Set(registry.tools(matching: .excluding(["selection_other"])).map(\.name)) == ["counting_echo"])
    #expect(registry.tools(matching: .including([])).isEmpty)
}

private struct SelectionOtherTool: AgentTool {
    struct Arguments: Codable, Sendable {}
    struct Output: Codable, Sendable {}

    static let name = "selection_other"
    static let description = "A second tool used for selection tests."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(properties: [:], required: []))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output()
    }
}
