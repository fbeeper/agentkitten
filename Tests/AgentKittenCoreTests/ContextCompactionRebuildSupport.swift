// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
@testable import AgentKittenInferenceTestSupport

struct RebuildingMockProvider: InferenceProviding {
    typealias Session = MockInferenceSession

    let responses: [String]

    nonisolated func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility {
        if current.provider != next.provider { return .replace }
        if current.toolSelection != next.toolSelection { return .rebuildSession }
        return .reuse
    }

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> MockInferenceSession {
        MockInferenceSession(
            responses: responses.map { .success($0) },
            toolRuntime: toolRuntime,
        )
    }

    func makeSession(
        continuing session: MockInferenceSession,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws -> MockInferenceSession {
        session
    }
}

struct ReplacementMockProvider: InferenceProviding {
    typealias Session = MockInferenceSession

    let responses: [String]

    func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> MockInferenceSession {
        MockInferenceSession(
            responses: responses.map { .success($0) },
            toolRuntime: toolRuntime,
        )
    }
}
