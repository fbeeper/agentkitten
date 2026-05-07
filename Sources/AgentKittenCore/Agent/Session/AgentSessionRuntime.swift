// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct AgentSessionRuntime {
    /// Shared runtime inputs for one routed turn.
    ///
    /// Kept internal rather than private so ``TurnValidator`` can reuse the same
    /// typed bundle without duplicating turn/trace/conversation plumbing.
    struct TurnRuntimeContext<Result: Sendable> {
        let turnRuntime: TurnRuntime<Result>
        let traceSink: TurnTraceSink
        let toolExecutionContext: ToolExecutionContext
        let conversation: AnyConversation
    }

    private let trace: AgentTrace
    private let approvalGate: ToolApprovalGate
    private let state: AgentSession.SessionStateAccess
    private let eventConsumer: ConversationEventConsumer

    init(
        agentID: AgentID,
        sessionID: AgentSessionID,
        trace: AgentTrace,
        approvalGate: ToolApprovalGate,
        state: AgentSession.SessionStateAccess
    ) {
        self.trace = trace
        self.approvalGate = approvalGate
        self.state = state
        self.eventConsumer = ConversationEventConsumer(
            agentID: agentID,
            sessionID: sessionID
        )
    }

    func routeTurn(
        userMessage: UserMessage,
        turnRuntime: TurnRuntime<AssistantMessage>,
        validation: ValidationConfiguration<AssistantMessage>,
        conversation: AnyConversation
    ) async throws {
        let executionConfiguration = EffectiveExecutionConfiguration(
            environment: turnRuntime.executionEnvironment
        )
        let context = TurnRuntimeContext(
            turnRuntime: turnRuntime,
            traceSink: makeTurnTraceSink(invocationID: turnRuntime.id),
            toolExecutionContext: makeToolExecutionContext(environment: turnRuntime.executionEnvironment),
            conversation: conversation
        )
        if validation.isEnabled {
            try await executeValidated(
                userMessage: userMessage,
                executionConfiguration: executionConfiguration,
                validation: validation,
                context: context
            )
        } else {
            try await executeDirect(
                userMessage: userMessage,
                executionConfiguration: executionConfiguration,
                context: context
            )
        }
    }

    func routeStructuredTurn<Result: Codable & Sendable & JSONSchemaProviding>(
        userMessage: UserMessage,
        turnRuntime: TurnRuntime<Result>,
        validation: ValidationConfiguration<Result>,
        conversation: AnyConversation
    ) async throws {
        let executionConfiguration = EffectiveExecutionConfiguration(
            environment: turnRuntime.executionEnvironment
        )
        let context = TurnRuntimeContext(
            turnRuntime: turnRuntime,
            traceSink: makeTurnTraceSink(invocationID: turnRuntime.id),
            toolExecutionContext: makeToolExecutionContext(environment: turnRuntime.executionEnvironment),
            conversation: conversation
        )
        if validation.isEnabled {
            try await executeStructuredValidated(
                userMessage: userMessage,
                executionConfiguration: executionConfiguration,
                validation: validation,
                context: context
            )
        } else {
            try await executeStructuredDirect(
                userMessage: userMessage,
                executionConfiguration: executionConfiguration,
                context: context
            )
        }
    }
}

extension AgentSessionRuntime {
    private func executeDirect(
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        context: TurnRuntimeContext<AssistantMessage>
    ) async throws {
        let stream = try await context.conversation.send(
            userMessage: userMessage,
            executionConfiguration: executionConfiguration,
            toolExecutionContext: context.toolExecutionContext
        )
        _ = try await eventConsumer.consume(
            stream,
            turnRuntime: context.turnRuntime,
            traceSink: context.traceSink,
            output: .emit
        ) as AssistantMessage
    }

    private func executeValidated(
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        validation: ValidationConfiguration<AssistantMessage>,
        context: TurnRuntimeContext<AssistantMessage>
    ) async throws {
        let generationStep: TurnValidator<AssistantMessage>.GenerationStep = { [eventConsumer] attemptMessage in
            let stream = try await context.conversation.send(
                userMessage: attemptMessage,
                executionConfiguration: executionConfiguration,
                toolExecutionContext: context.toolExecutionContext
            )
            return try await eventConsumer.consume(
                stream,
                turnRuntime: context.turnRuntime,
                traceSink: context.traceSink,
                output: .emitTools
            ) as AssistantMessage
        }
        try await TurnValidator<AssistantMessage>(
            configuration: validation,
            sessionState: state,
            consumer: eventConsumer
        ).run(
            generationStep: generationStep,
            userMessage: userMessage,
            context: context
        )
    }

    private func executeStructuredDirect<Result: Codable & Sendable & JSONSchemaProviding>(
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        context: TurnRuntimeContext<Result>
    ) async throws {
        let stream: AsyncThrowingStream<ConversationEvent<Result>, Error> =
            try await context.conversation.generate(
                userMessage: userMessage,
                executionConfiguration: executionConfiguration,
                toolExecutionContext: context.toolExecutionContext
            )
        // The final typed result is emitted into the turn stream by the consumer.
        _ = try await eventConsumer.consume(
            stream,
            turnRuntime: context.turnRuntime,
            traceSink: context.traceSink,
            output: .emit
        ) as Result
    }

    private func executeStructuredValidated<Result: Codable & Sendable & JSONSchemaProviding>(
        userMessage: UserMessage,
        executionConfiguration: EffectiveExecutionConfiguration,
        validation: ValidationConfiguration<Result>,
        context: TurnRuntimeContext<Result>
    ) async throws {
        let generationStep: TurnValidator<Result>.GenerationStep = { [eventConsumer] attemptMessage in
            let stream: AsyncThrowingStream<ConversationEvent<Result>, Error> =
                try await context.conversation.generate(
                    userMessage: attemptMessage,
                    executionConfiguration: executionConfiguration,
                    toolExecutionContext: context.toolExecutionContext
                )
            return try await eventConsumer.consume(
                stream,
                turnRuntime: context.turnRuntime,
                traceSink: context.traceSink,
                output: .emitTools
            ) as Result
        }
        try await TurnValidator<Result>(
            configuration: validation,
            sessionState: state,
            consumer: eventConsumer
        ).run(
            generationStep: generationStep,
            userMessage: userMessage,
            context: context
        )
    }
}

extension AgentSessionRuntime {
    private func makeTurnTraceSink(
        invocationID: InvocationID
    ) -> TurnTraceSink {
        TurnTraceSink(
            trace: trace,
            approvalGate: approvalGate,
            invocationID: invocationID
        )
    }

    private func makeToolExecutionContext(environment: ExecutionEnvironment) -> ToolExecutionContext {
        ToolExecutionContext(customValues: environment.customValues(for: .toolApproval))
    }
}
