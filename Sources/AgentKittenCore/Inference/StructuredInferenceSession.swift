// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Single-shot typed-value generation support for inference sessions.
///
/// `StructuredInferenceSession` is the typed-value counterpart to ``InferenceSession``.
/// Providers may expose it on dedicated single-purpose sessions or on their regular
/// conversation session actors.
///
/// Create one via
/// ``InferenceProviding/makeSession(systemPrompt:toolRuntime:toolSelection:inferenceContext:)``
/// and call the structured methods when typed output is needed.
///
/// We cannot express a single associated stream type here because the output event
/// payload is itself generic over `T`.
public typealias StructuredInferenceStream<T: Sendable> =
    AsyncThrowingStream<InferenceEvent<T>, Error>

public protocol StructuredInferenceSession: Actor {
    /// Starts a structured generation event stream for the given prompt.
    ///
    /// Iterate the returned stream to observe streaming text deltas, tool-call
    /// events, and the final structured result.
    ///
    /// `parameters.toolSelection` is the turn-level tool policy from the
    /// conversation layer. Structured providers must honor it using the same
    /// mechanism as unstructured turns.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt for this turn.
    ///   - parameters: Generation settings and tool selection for this turn.
    /// - Returns: A stream of structured inference events ending with `.result`.
    /// - Throws: Underlying provider/session errors for operation failures, or
    ///   ``StructuredGenerationError`` for structured-output-specific failures.
    func generateStream<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws
        -> StructuredInferenceStream<T>

    /// Generates a single typed value for the given prompt.
    ///
    /// The provider constrains the model's response format using `T`'s
    /// ``JSONSchemaProviding/jsonSchema`` and decodes the response into `T`.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt for this turn.
    ///   - parameters: Generation settings and tool selection for this turn.
    /// - Returns: The decoded typed value.
    /// - Throws: Underlying provider/session errors for operation failures, or
    ///   ``StructuredGenerationError`` for structured-output-specific failures.
    func generate<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws -> T
}

extension StructuredInferenceSession {
    public func generate<T: Codable & Sendable & JSONSchemaProviding>(
        prompt: String,
        parameters: InferenceRequestParameters,
    ) async throws -> T {
        let stream: StructuredInferenceStream<T> = try await generateStream(prompt: prompt, parameters: parameters)
        for try await event in stream {
            if case .result(let result, _) = event {
                return result
            }
        }
        throw StructuredGenerationError.generationFailed(
            StructuredGenerationStreamError.missingResult,
        )
    }
}

/// Errors that can occur during structured output generation.
public enum StructuredGenerationError: Error {
    /// The model's response could not be decoded into the requested type.
    ///
    /// - Parameter error: The underlying decoding error.
    case decodingFailed(any Error)

    /// The underlying provider call failed before a response was received.
    ///
    /// - Parameter error: The underlying provider or network error.
    case generationFailed(any Error)
}

private enum StructuredGenerationStreamError: Error {
    case missingResult
}
