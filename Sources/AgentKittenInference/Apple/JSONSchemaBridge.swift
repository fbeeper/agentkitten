// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
import FoundationModels

/// Converts AgentKitten's ``ToolSchema`` / ``JSONSchema`` to FoundationModels schema types.
///
/// The entry point is ``ToolSchema/toGenerationSchema(toolName:)``.
/// Each ``JSONSchema`` case maps to a ``DynamicGenerationSchema``, which is then
/// compiled into a ``GenerationSchema`` via `init(root:dependencies:)`.
///
/// Primitive types (`String`, `Int`, `Double`, `Bool`) use
/// `DynamicGenerationSchema(type:)`, relying on their built-in `Generable`
/// conformances in FoundationModels. Enumerations are represented as `String` with
/// the allowed values appended to the property description — `DynamicGenerationSchema`
/// has no native enum case.
@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension ToolSchema {
    /// Converts this tool schema to a ``GenerationSchema`` for use as `Tool.parameters`.
    ///
    /// - Parameter toolName: Used as the root object schema name; typically the tool's
    ///   routing name (e.g. `"get_weather"`).
    /// - Throws: `GenerationSchema.SchemaError` if the schema graph is invalid
    ///   (e.g. duplicate property names).
    func toGenerationSchema(toolName: String, rationaleDescription: String) throws -> GenerationSchema {
        let root = parameters.injectingRationale(description: rationaleDescription)
            .toDynamicSchema(name: toolName + "Arguments")
        return try GenerationSchema(root: root, dependencies: [])
    }
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension JSONSchema {
    /// Recursively converts to a ``DynamicGenerationSchema``.
    func toDynamicSchema(name: String) -> DynamicGenerationSchema {
        switch self {
        case .string:
            return DynamicGenerationSchema(type: String.self)
        case .integer:
            // DynamicGenerationSchema only supports Int.self. Unsigned types (UInt*)
            // and narrow signed types (Int8/16/32) declared in Arguments are all
            // represented as Int — no range constraint is communicated to the model.
            // The model may generate values outside the original type's domain, which
            // will fail Codable decoding. The @Tool macro emits a compile-time warning
            // for affected types to surface this before runtime.
            return DynamicGenerationSchema(type: Int.self)
        case .number:
            return DynamicGenerationSchema(type: Double.self)
        case .boolean:
            return DynamicGenerationSchema(type: Bool.self)
        case .array(let items, _):
            return DynamicGenerationSchema(arrayOf: items.toDynamicSchema(name: name + "Element"))
        case .object(let properties, let required):
            let props = properties.sorted(by: { $0.key < $1.key }).map { key, schema in
                DynamicGenerationSchema.Property(
                    name: key,
                    description: schema.propertyDescription,
                    schema: schema.toDynamicSchema(name: key),
                    isOptional: !required.contains(key)
                )
            }
            return DynamicGenerationSchema(name: name, description: nil, properties: props)
        case .enumeration:
            // No native enum case in DynamicGenerationSchema.
            // Represent as String; allowed values are surfaced via propertyDescription
            // on the DynamicGenerationSchema.Property wrapping this schema.
            return DynamicGenerationSchema(type: String.self)
        }
    }

    fileprivate func injectingRationale(description: String) -> JSONSchema {
        guard case .object(var props, var required) = self else {
            return self
        }
        props[ToolRationale.schemaKey] = .string(description: description)
        required.append(ToolRationale.schemaKey)
        return .object(properties: props, required: required)
    }

    /// The natural-language description to surface as a `DynamicGenerationSchema.Property`
    /// description. `nil` for object schemas (they carry their own description).
    var propertyDescription: String? {
        switch self {
        case .string(let desc), .integer(let desc), .number(let desc), .boolean(let desc):
            return desc
        case .array(_, let desc):
            return desc
        case .enumeration(let values, let desc):
            let prefix = AgentKittenInferenceLocalization.string("contextCompaction.enumOneOfPrefix")
            let valuesClause = "\(prefix) \(values.joined(separator: ", "))"
            if let desc {
                return "\(desc). \(valuesClause)"
            }
            return valuesClause
        case .object:
            return nil
        }
    }
}
#endif
