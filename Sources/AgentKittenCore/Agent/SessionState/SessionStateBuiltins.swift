// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

enum SessionStateBuiltins {
    static let reservedNames: Set<String> = [
        GetStateTool.name,
        ListStateKeysTool.name,
        SetStateTool.name,
        RemoveStateTool.name,
    ]

    static func makeReadOnlyTools(
        state: SessionState,
        config: SessionStateConfiguration = SessionStateConfiguration(),
    ) -> [AnyAgentTool] {
        [
            AnyAgentTool(GetStateTool(state: state, config: config)),
            AnyAgentTool(ListStateKeysTool(state: state, config: config)),
        ]
    }

    static func makeTools(
        state: SessionState,
        config: SessionStateConfiguration = SessionStateConfiguration(),
    ) -> [AnyAgentTool] {
        makeReadOnlyTools(state: state, config: config) + [
            AnyAgentTool(SetStateTool(state: state, config: config)),
            AnyAgentTool(RemoveStateTool(state: state, config: config)),
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
    static var defaultDescription: String {
        preconditionFailure("Use instance description")
    }

    let description: String
    let state: SessionState
    private let keyDescription: String

    init(state: SessionState, config: SessionStateConfiguration) {
        self.state = state
        description = config.getStateDescription
        keyDescription = config.getStateKeyDescription
    }

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "key": .string(description: keyDescription),
            ],
            required: ["key"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(value: await state.value(forKey: arguments.key))
    }
}

private struct ListStateKeysTool: AgentTool {
    struct Arguments: Codable, Sendable {}

    struct Output: Codable, Sendable, Equatable {
        let keys: [String]
    }

    static let name = "list_state_keys"
    static var defaultDescription: String {
        preconditionFailure("Use instance description")
    }

    let description: String
    let state: SessionState

    init(state: SessionState, config: SessionStateConfiguration) {
        self.state = state
        description = config.listStateKeysDescription
    }

    var schema: ToolSchema {
        ToolSchema(parameters: .object(properties: [:], required: []))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(keys: await state.contents().keys.sorted())
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
    static var defaultDescription: String {
        preconditionFailure("Use instance description")
    }

    let description: String
    let state: SessionState
    private let keyDescription: String
    private let valueDescription: String

    init(state: SessionState, config: SessionStateConfiguration) {
        self.state = state
        description = config.setStateDescription
        keyDescription = config.setStateKeyDescription
        valueDescription = config.setStateValueDescription
    }

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "key": .string(description: keyDescription),
                "value": .string(description: valueDescription),
            ],
            required: ["key", "value"],
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
    static var defaultDescription: String {
        preconditionFailure("Use instance description")
    }

    let description: String
    let state: SessionState
    private let keyDescription: String

    init(state: SessionState, config: SessionStateConfiguration) {
        self.state = state
        description = config.removeStateDescription
        keyDescription = config.removeStateKeyDescription
    }

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "key": .string(description: keyDescription),
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
