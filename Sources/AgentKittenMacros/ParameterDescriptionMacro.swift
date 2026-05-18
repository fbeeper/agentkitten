// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftSyntax
import SwiftSyntaxMacros

/// Implements the `@ParameterDescription` peer macro.
///
/// Expands to zero declarations — the attribute exists purely as an annotation
/// that the ``ToolMacro`` reads when generating the ``ToolSchema``.
public struct ParameterDescriptionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        // No additional declarations generated; presence of the attribute is the signal.
        []
    }
}
