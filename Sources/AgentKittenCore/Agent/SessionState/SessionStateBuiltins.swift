// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

enum SessionStateBuiltins {
    static let reservedNames: Set<String> = [
        GetStateTool.name,
        ListStateKeysTool.name,
        SetStateTool.name,
        RemoveStateTool.name,
    ]

    static func makeReadOnlyTools(state: SessionState) -> [AnyAgentTool] {
        [
            AnyAgentTool(GetStateTool(state: state)),
            AnyAgentTool(ListStateKeysTool(state: state)),
        ]
    }

    static func makeTools(state: SessionState) -> [AnyAgentTool] {
        makeReadOnlyTools(state: state) + [
            AnyAgentTool(SetStateTool(state: state)),
            AnyAgentTool(RemoveStateTool(state: state)),
        ]
    }
}

private struct GetStateTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let key: String
    }

    struct Output: Codable, Sendable, Equatable {
        let value: String?
    }

    static let name = "get_state"
    static var description: String { AgentKittenLocalization.string("sessionState.getStateDescription") }

    let state: SessionState

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "key": .string(description: AgentKittenLocalization.string("sessionState.getStateKeyDescription")),
            ],
            required: ["key"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        let value = await state.value(forKey: arguments.key)
        return Output(value: value)
    }
}

private struct ListStateKeysTool: AgentTool {
    struct Arguments: Codable, Sendable {}

    struct Output: Codable, Sendable, Equatable {
        let keys: [String]
    }

    static let name = "list_state_keys"
    static var description: String { AgentKittenLocalization.string("sessionState.listStateKeysDescription") }

    let state: SessionState

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [:],
            required: [],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        let keys = await state.contents().keys.sorted()
        return Output(keys: keys)
    }
}

private struct SetStateTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let key: String
        let value: String
    }

    struct Output: Codable, Sendable, Equatable {
        let key: String
    }

    static let name = "set_state"
    static var description: String { AgentKittenLocalization.string("sessionState.setStateDescription") }

    let state: SessionState

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "key": .string(description: AgentKittenLocalization.string("sessionState.setStateKeyDescription")),
                "value": .string(
                    description: AgentKittenLocalization.string("sessionState.setStateValueDescription")
                ),
            ],
            required: [
                "key",
                "value",
            ],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        try await state.setValue(arguments.value, forKey: arguments.key)
        return Output(key: arguments.key)
    }
}

private struct RemoveStateTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let key: String
    }

    struct Output: Codable, Sendable, Equatable {
        let key: String
        let removed: Bool
    }

    static let name = "remove_state"
    static var description: String { AgentKittenLocalization.string("sessionState.removeStateDescription") }

    let state: SessionState

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "key": .string(description: AgentKittenLocalization.string("sessionState.removeStateKeyDescription")),
            ],
            required: ["key"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(
            key: arguments.key,
            removed: try await state.removeValue(forKey: arguments.key),
        )
    }
}
