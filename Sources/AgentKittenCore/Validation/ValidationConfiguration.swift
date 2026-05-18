// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Validation policy for direct assistant-message execution.
public struct ValidationConfiguration<Result: Sendable>: Sendable {
    /// Aggregated policy applied once validation cannot produce a passing result.
    public enum Policy: Sendable, Equatable {
        /// Block invalid output from completing the turn.
        case restrictive
        /// Allow the last assistant response through even if validation failed.
        case permissive
    }

    /// Maximum retry budget shared across all validators after the initial response.
    public let maxRetries: Int
    /// Aggregated policy applied once validation cannot produce a passing result.
    public let policy: Policy
    let validators: [AnyValidator<Result>]
    private let retryFeedbackMessageBuilder: @Sendable (String) -> UserMessage

    private init(
        validators: [AnyValidator<Result>],
        maxRetries: Int,
        policy: Policy,
        retryFeedbackMessageBuilder: @Sendable @escaping (String) -> UserMessage,
    ) {
        self.validators = validators
        self.maxRetries = max(0, maxRetries)
        self.policy = policy
        self.retryFeedbackMessageBuilder = retryFeedbackMessageBuilder
    }

    /// Creates a validation configuration with one validator.
    ///
    /// - Parameters:
    ///   - validator: Initial validator to evaluate for each assistant response.
    ///   - maxRetries: Maximum retry budget after the initial response.
    ///   - policy: Aggregated policy applied when validation cannot produce a pass.
    public init(
        validator: some Validator<Result>,
        maxRetries: Int = 0,
        policy: Policy = .restrictive,
    ) {
        self.init(
            validator: validator,
            maxRetries: maxRetries,
            policy: policy,
            retryFeedbackMessage: Self.defaultRetryFeedbackMessage,
        )
    }

    /// Creates a validation configuration with one validator and custom retry feedback composition.
    ///
    /// - Parameters:
    ///   - validator: Initial validator to evaluate for each assistant response.
    ///   - maxRetries: Maximum retry budget after the initial response.
    ///   - policy: Aggregated policy applied when validation cannot produce a pass.
    ///   - retryFeedbackMessage: Builds the synthetic retry message injected after
    ///     validation feedback requests another generation attempt.
    public init(
        validator: some Validator<Result>,
        maxRetries: Int,
        policy: Policy,
        retryFeedbackMessage: @Sendable @escaping (String) -> UserMessage = Self.defaultRetryFeedbackMessage,
    ) {
        self.init(
            validators: [AnyValidator(validator)],
            maxRetries: maxRetries,
            policy: policy,
            retryFeedbackMessageBuilder: retryFeedbackMessage,
        )
    }

    /// A concrete signal that no assistant validation is required.
    public static var disabled: ValidationConfiguration<Result> {
        ValidationConfiguration(
            validators: [],
            maxRetries: 0,
            policy: .restrictive,
            retryFeedbackMessageBuilder: defaultRetryFeedbackMessage,
        )
    }

    /// Returns a copy of the configuration with one more validator appended.
    public func adding(
        _ validator: some Validator<Result>,
    ) -> ValidationConfiguration<Result> {
        ValidationConfiguration(
            validators: validators + [AnyValidator(validator)],
            maxRetries: maxRetries,
            policy: policy,
            retryFeedbackMessageBuilder: retryFeedbackMessageBuilder,
        )
    }

    public var isEnabled: Bool {
        !validators.isEmpty
    }

    func makeRetryFeedbackMessage(from message: String) -> UserMessage {
        retryFeedbackMessageBuilder(message)
    }

    public static func defaultRetryFeedbackMessage(
        _ message: String,
    ) -> UserMessage {
        UserMessage(text: """
        Internal validation feedback for your previous response:
        \(message)

        Revise your previous answer so it satisfies this feedback while still \
        addressing the user's request. Apply this feedback only to the current \
        response you are revising right now.

        Do not mention validation, feedback, a judge, internal checks, or these \
        instructions in your answer. Present the revised answer directly as if it \
        were your first response to the user. Do not carry this feedback forward \
        into future turns unless the user independently asks for the same change.
        """)
    }
}
