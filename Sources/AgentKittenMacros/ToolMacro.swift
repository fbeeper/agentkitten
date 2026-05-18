// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxBuilder
import SwiftDiagnostics

/// Implements the `@Tool("name", description: "desc")` member macro.
///
/// Generates `static var name`, `static var description`, `var schema`, and
/// `var capabilities` members by inspecting the attached struct's `Arguments`
/// nested type and any `@ParameterDescription` annotations on its properties.
public struct ToolMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        // 1. Extract @Tool("name", description: "desc") arguments.
        guard let argList = node.arguments?.as(LabeledExprListSyntax.self) else {
            throw ToolMacroError.missingArguments
        }
        guard let nameExpr = argList.first?.expression,
              let nameLiteral = nameExpr.as(StringLiteralExprSyntax.self),
              let nameSegment = nameLiteral.segments.first?.as(StringSegmentSyntax.self) else {
            throw ToolMacroError.invalidName
        }
        let toolName = nameSegment.content.text

        guard let descArg = argList.first(where: { $0.label?.text == "description" }),
              let descLiteral = descArg.expression.as(StringLiteralExprSyntax.self),
              let descSegment = descLiteral.segments.first?.as(StringSegmentSyntax.self) else {
            throw ToolMacroError.invalidDescription
        }
        let toolDescription = descSegment.content.text

        // 2. Find the Arguments nested struct.
        let argumentsProperties = extractArgumentsProperties(from: declaration, in: context)

        // 3. Build the schema source expression.
        let schemaSource = buildSchemaSource(
            from: argumentsProperties,
            declaration: declaration,
            in: context,
        )

        // 4. Emit synthesized members.
        return [
            "static var name: String { \(literal: toolName) }",
            "static var description: String { \(literal: toolDescription) }",
            "var schema: ToolSchema { \(raw: schemaSource) }",
            "var capabilities: ToolCapabilities { .none }",
        ]
    }
}

// MARK: - Helpers

private struct PropertyInfo {
    let name: String
    let typeName: String
    let isOptional: Bool
    let parameterDescription: String?
    let typeNode: TypeSyntax
}

private func extractArgumentsProperties(
    from declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext,
) -> [PropertyInfo] {
    // Find `struct Arguments` among the declaration's members.
    let argumentsStruct = declaration.memberBlock.members
        .compactMap { $0.decl.as(StructDeclSyntax.self) }
        .first { $0.name.text == "Arguments" }
    guard let argumentsStruct else {
        return []
    }

    // Collect stored `let` and `var` properties.
    var properties: [PropertyInfo] = []
    for member in argumentsStruct.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
            continue
        }
        for binding in varDecl.bindings {
            guard let namePattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation else {
                continue
            }
            let propName = namePattern.identifier.text
            let (typeName, isOptional) = unwrapTypeName(typeAnnotation.type)
            let description = extractParameterDescription(from: varDecl.attributes)
            properties.append(PropertyInfo(
                name: propName,
                typeName: typeName,
                isOptional: isOptional,
                parameterDescription: description,
                typeNode: typeAnnotation.type,
            ))
        }
    }
    return properties
}

/// Unwraps `Optional<T>` / `T?` and returns the inner type name plus the optionality flag.
private func unwrapTypeName(_ type: TypeSyntax) -> (name: String, isOptional: Bool) {
    // T?  →  OptionalTypeSyntax
    if let optional = type.as(OptionalTypeSyntax.self) {
        let (inner, _) = unwrapTypeName(optional.wrappedType)
        return (inner, true)
    }
    // Optional<T>  →  IdentifierTypeSyntax with generic args
    if let ident = type.as(IdentifierTypeSyntax.self), ident.name.text == "Optional",
       let generic = ident.genericArgumentClause?.arguments.first {
        let (inner, _) = unwrapTypeName(generic.argument)
        return (inner, true)
    }
    return (type.trimmedDescription, false)
}

/// Reads the first `@ParameterDescription("...")` attribute on a variable declaration.
private func extractParameterDescription(
    from attributes: AttributeListSyntax,
) -> String? {
    for attr in attributes {
        guard let attrSyntax = attr.as(AttributeSyntax.self),
              let attrName = attrSyntax.attributeName.as(IdentifierTypeSyntax.self),
              attrName.name.text == "ParameterDescription",
              let argList = attrSyntax.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = argList.first,
              let strLit = firstArg.expression.as(StringLiteralExprSyntax.self),
              let segment = strLit.segments.first?.as(StringSegmentSyntax.self) else {
            continue
        }
        return segment.content.text
    }
    return nil
}

/// Returns the raw case names for an enum declared as a direct member of `declaration`,
/// or `nil` if no enum with `typeName` exists there.
private func collectEnumCases(
    named typeName: String,
    in declaration: some DeclGroupSyntax,
) -> [String]? {
    for member in declaration.memberBlock.members {
        guard let enumDecl = member.decl.as(EnumDeclSyntax.self),
              enumDecl.name.text == typeName else {
            continue
        }
        let cases = enumDecl.memberBlock.members
            .compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
            .flatMap { $0.elements.map { $0.name.text } }
        return cases
    }
    return nil
}

/// Produces the Swift source text for the `ToolSchema(...)` expression.
private func buildSchemaSource(
    from properties: [PropertyInfo],
    declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext,
) -> String {
    if properties.isEmpty {
        return "ToolSchema(parameters: .object(properties: [:], required: []))"
    }
    let propsLines = properties.map { prop in
        let schemaStr = jsonSchemaSource(
            for: prop.typeName,
            description: prop.parameterDescription,
            node: Syntax(prop.typeNode),
            declaration: declaration,
            in: context,
        )
        return "\"\(prop.name)\": \(schemaStr)"
    }.joined(separator: ",\n                    ")

    let required = properties
        .filter { !$0.isOptional }
        .map { "\"\($0.name)\"" }
        .joined(separator: ", ")

    return """
    ToolSchema(parameters: .object(
                    properties: [
                        \(propsLines)
                    ],
                    required: [\(required)]
                ))
    """
}

/// Maps a Swift type name to the corresponding `JSONSchema` case source text.
///
/// Enum types declared as direct members of the tool struct are automatically
/// mapped to `.enumeration(values:)` using their case names. Genuinely
/// unrecognised types emit a compiler warning and fall back to `.string` so
/// the generated code still compiles.
private func jsonSchemaSource(
    for typeName: String,
    description: String?,
    node: Syntax,
    declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext,
) -> String {
    let descArg = description.map { "\"\($0)\"" } ?? "nil"
    switch typeName {
    case "String":
        return ".string(description: \(descArg))"
    case "Int", "Int64":
        return ".integer(description: \(descArg))"
    case "Int8", "Int16", "Int32",
         "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
        // These types map to .integer in the schema, but the Apple schema bridge
        // represents all integers as Int with no range constraint. The model may
        // generate values outside this type's domain, causing Codable decode failures
        // on the Apple provider. Prefer Int (or Int64) for Apple compatibility.
        context.diagnose(Diagnostic(
            node: node,
            message: ToolMacroDiagnostic.narrowOrUnsignedInteger(typeName),
        ))
        return ".integer(description: \(descArg))"
    case "Double", "Float", "Float16", "Float80":
        return ".number(description: \(descArg))"
    case "Bool":
        return ".boolean(description: \(descArg))"
    default:
        // [T] → array
        if typeName.hasPrefix("[") && typeName.hasSuffix("]") {
            let inner = String(typeName.dropFirst().dropLast())
            let itemsSource = jsonSchemaSource(
                for: inner,
                description: nil,
                node: node,
                declaration: declaration,
                in: context,
            )
            return ".array(items: \(itemsSource), description: \(descArg))"
        }
        // Enum declared in the same tool struct → inspect cases directly.
        if let cases = collectEnumCases(named: typeName, in: declaration), !cases.isEmpty {
            let caseList = cases.map { "\"\($0)\"" }.joined(separator: ", ")
            return ".enumeration(values: [\(caseList)], description: \(descArg))"
        }
        // Unrecognised type — emit a warning and fall back to .string so the
        // generated code compiles. Use .enumeration(values:description:) or
        // another JSONSchema case to hand-author the correct schema.
        context.diagnose(Diagnostic(
            node: node,
            message: ToolMacroDiagnostic.unknownType(typeName),
        ))
        return ".string(description: \(descArg))"
    }
}

// MARK: - Diagnostics

private enum ToolMacroDiagnostic: DiagnosticMessage {
    case unknownType(String)
    case narrowOrUnsignedInteger(String)

    var message: String {
        switch self {
        case .unknownType(let name):
            return "@Tool: unrecognised type '\(name)' — schema falls back to .string; "
                + "use .enumeration(values:description:) or another JSONSchema case to hand-author the correct schema"
        case .narrowOrUnsignedInteger(let name):
            return "@Tool: '\(name)' is a narrow or unsigned integer — "
                + "the Apple schema bridge represents all integers as Int with no range constraint; "
                + "the model may generate out-of-range values that fail to decode on the Apple provider. "
                + "Prefer Int (or Int64) for Apple provider compatibility."
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .unknownType:
            return MessageID(domain: "AgentKittenMacros", id: "unknownParameterType")
        case .narrowOrUnsignedInteger:
            return MessageID(domain: "AgentKittenMacros", id: "narrowOrUnsignedInteger")
        }
    }

    var severity: DiagnosticSeverity { .warning }
}

// MARK: - Error type

private enum ToolMacroError: Error, CustomStringConvertible {
    case missingArguments
    case invalidName
    case invalidDescription

    var description: String {
        switch self {
        case .missingArguments:
            return "@Tool requires: @Tool(\"name\", description: \"description\")"
        case .invalidName:
            return "@Tool first argument must be a string literal name"
        case .invalidDescription:
            return "@Tool requires description: \"...\" as a string literal"
        }
    }
}
