// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A typed, recursive JSON Schema representation.
///
/// Cases map 1:1 to App Intents `@Parameter` types to preserve forward compatibility
/// with the future `AssistantIntent` bridge.
public indirect enum JSONSchema: Sendable, Codable {
    /// An object with named, typed properties.
    case object(properties: [String: JSONSchema], required: [String])
    /// A string value.
    case string(description: String?)
    /// A whole-number value.
    case integer(description: String?)
    /// A floating-point value.
    case number(description: String?)
    /// A boolean value.
    case boolean(description: String?)
    /// An ordered sequence of items with a uniform element schema.
    case array(items: JSONSchema, description: String?)
    /// A string value constrained to a fixed set of raw string cases.
    case enumeration(values: [String], description: String?)
}
