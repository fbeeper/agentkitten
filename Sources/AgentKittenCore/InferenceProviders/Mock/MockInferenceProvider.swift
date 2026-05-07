// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import os

private let logger = Logger(subsystem: "AgentKittenCore", category: "MockInferenceProvider")

/// A mock ``InferenceProviding`` conformer that returns canned responses.
///
/// Use in tests and previews. Each conversation gets a fresh
/// ``MockInferenceSession`` that cycles through the provided responses in
/// order, wrapping around when exhausted. Structured sessions cycle through
/// `structuredResponses` (pre-encoded JSON strings) the same way.
///
/// Public so library consumers can use it in their own test targets.
public actor MockInferenceProvider: InferenceProviding {
    private let responses: [MockResponse]
    private let structuredResponses: [String]
    private let structuredMockResponses: [MockResponse]

    /// Creates a mock provider that cycles through the given text responses.
    ///
    /// - Parameters:
    ///   - responses: The canned response strings for regular sessions.
    ///     Defaults to a single generic placeholder string.
    ///   - structuredResponses: Pre-encoded JSON strings for structured sessions.
    ///     Defaults to empty, which causes ``MockInferenceSession`` to throw
    ///     ``StructuredGenerationError/generationFailed(_:)`` on every call.
    public init(
        responses: [String] = ["This is a mock response."],
        structuredResponses: [String] = [],
        structuredMockResponses: [MockResponse] = []
    ) {
        self.responses = responses.map { .success($0) }
        self.structuredResponses = structuredResponses
        self.structuredMockResponses = structuredMockResponses
    }

    /// Creates a mock provider that cycles through the given mock responses.
    ///
    /// Use this initializer to test both success and error paths.
    ///
    /// If `mockResponses` is empty a fallback success response is substituted
    /// and an error is logged, so no crash occurs.
    ///
    /// - Parameters:
    ///   - mockResponses: The canned responses to return in order.
    ///   - structuredResponses: Pre-encoded JSON strings for structured sessions.
    public init(
        mockResponses: [MockResponse],
        structuredResponses: [String] = [],
        structuredMockResponses: [MockResponse] = []
    ) {
        if mockResponses.isEmpty {
            logger.error("MockInferenceProvider initialized with empty responses; using fallback.")
            self.responses = [.success("This is a mock response.")]
        } else {
            self.responses = mockResponses
        }
        self.structuredResponses = structuredResponses
        self.structuredMockResponses = structuredMockResponses
    }

    /// Creates a new mock session for a single conversation thread.
    public nonisolated func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext = .empty
    ) -> MockInferenceSession {
        MockInferenceSession(
            responses: responses,
            structuredResponses: structuredResponses,
            structuredMockResponses: structuredMockResponses,
            toolRuntime: toolRuntime
        )
    }
}
