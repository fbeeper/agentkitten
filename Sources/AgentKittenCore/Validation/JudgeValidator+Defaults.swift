// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

extension JudgeValidator {
    /// Default format string for the judge system prompt (criteria case); takes one `%@`.
    public static var defaultJudgeSystemPromptFormat: String {
        """
        You are a validation judge for another AI assistant's response.

        Evaluate the candidate result against the original user request and the \
        validation criteria below.

        Validation criteria:
        %@

        Prefer feedback over fail when a revised answer could satisfy the criteria. \
        Use fail only when the result should be rejected rather than retried.
        """
    }

    /// Default guidance appended to the system prompt for verdict format.
    public static var defaultJudgeVerdictGuidance: String {
        """
        Return one structured decision:
        - pass: the result satisfies the criteria
        - fail: the result is invalid and should be rejected
        - feedback: the result could be improved by another assistant attempt
        """
    }

    /// Default format string for the judge user prompt; takes two `%@` arguments.
    public static var defaultJudgeUserPromptFormat: String {
        """
        Original user message:
        %1$@

        Candidate result:
        %2$@

        Evaluate the candidate result against the criteria from your system \
        instructions and return the structured verdict.
        """
    }

    /// Default fallback reason when the judge rejects without a message.
    public static var defaultJudgeRejectionMessage: String {
        "Judge rejected the result."
    }

    /// Default fallback message when the judge requests revision without a message.
    public static var defaultJudgeRevisionMessage: String {
        "Judge requested a revised result."
    }
}
