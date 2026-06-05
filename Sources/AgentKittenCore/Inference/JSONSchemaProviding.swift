// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Declares a type's JSON schema for structured output.
///
/// Conform types that are used as the output of ``StructuredInferenceSession/generate(prompt:parameters:)``
/// to this protocol. The static ``jsonSchema`` property tells the provider how to constrain
/// the model's response format so it can be decoded into `Self`.
///
/// ```swift
/// struct TaskClassification: Decodable, Sendable, JSONSchemaProviding {
///     let complexity: String
///     let estimatedSteps: Int
///
///     static var jsonSchema: JSONSchema {
///         .object(
///             properties: [
///                 "complexity": .string(description: "low, medium, or high"),
///                 "estimatedSteps": .integer(description: "Estimated number of steps"),
///             ],
///             required: ["complexity", "estimatedSteps"]
///         )
///     }
/// }
/// ```
public protocol JSONSchemaProviding {
    /// The JSON schema describing this type's structure.
    ///
    /// Providers use this schema to constrain the model's response so it can be
    /// decoded into `Self`. The schema must match the type's `Decodable` implementation.
    static var jsonSchema: JSONSchema { get }
}

extension Array: JSONSchemaProviding where Element: JSONSchemaProviding {
    public static var jsonSchema: JSONSchema {
        .array(items: Element.jsonSchema, description: nil)
    }
}
