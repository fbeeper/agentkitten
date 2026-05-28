// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
import Foundation

/// Decodes a JSON string into a strongly-typed value, wrapping failures as ``StructuredGenerationError``.
public func decodeStructuredValue<T: Decodable>(
    _ type: T.Type,
    from json: String,
) throws(StructuredGenerationError) -> T {
    do {
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    } catch {
        throw StructuredGenerationError.decodingFailed(error)
    }
}

/// Encodes a ``JSONSchema`` to a compact JSON string suitable for embedding in a system prompt.
public func encodeStructuredSchema(_ schema: JSONSchema) -> String {
    let value = InferenceProviderJSONValue.encoding(schema)
    guard let data = try? JSONEncoder().encode(value),
          let str = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return str
}

/// Builds the effective system prompt for a structured generation request.
///
/// Injects the schema JSON into `format` and prepends `systemPrompt` when present.
public func buildStructuredSystemPrompt(
    schemaJSON: String,
    systemPrompt: String?,
    format: String,
) -> String {
    let instruction = String(format: format, schemaJSON)
    if let systemPrompt, !systemPrompt.isEmpty {
        return "\(systemPrompt)\n\n\(instruction)"
    }
    return instruction
}
