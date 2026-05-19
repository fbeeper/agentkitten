// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Synthesizes `name`, `defaultDescription`, `schema`, and `capabilities` for a concrete ``AgentTool``.
///
/// Attach to a struct conforming to ``AgentTool``. The macro reads the `Arguments`
/// nested struct and generates a ``ToolSchema`` from its stored properties.
///
/// ```swift
/// @Tool("get_weather", description: "Returns current weather for a location.")
/// struct GetWeatherTool: AgentTool {
///     struct Arguments: Codable, Sendable {
///         @ParameterDescription("City and state, e.g. 'Austin, TX'")
///         let location: String
///     }
///     struct Output: Codable, Sendable { let temperature: Double; let condition: String }
///     func execute(arguments: Arguments) async throws -> Output { ... }
/// }
/// ```
///
/// ## Type mapping
/// | Swift type | JSONSchema case |
/// |---|---|
/// | `String` | `.string` |
/// | `Int`, `Int64` | `.integer` |
/// | `Int8`, `Int16`, `Int32`, `UInt*` | `.integer` — **warning emitted**; Apple bridge uses `Int` |
/// | `Double`, `Float` | `.number` |
/// | `Bool` | `.boolean` |
/// | `[T]` | `.array(items:)` |
/// | `T?` | unwrapped type; not in `required` |
/// | `enum` defined inside the same tool struct | `.enumeration(values:)` — cases auto-inspected |
/// | external `enum` or unrecognised type | compile-time **warning**; falls back to `.string` |
///
/// Use `@ParameterDescription` on stored properties in `Arguments` to supply per-parameter
/// descriptions. Unrecognised types (including enums not defined in the same struct) produce
/// a compile-time warning and fall back to `.string`.
@attached(member, names: named(name), named(defaultDescription), named(schema), named(capabilities))
public macro Tool(_ name: String, description: String) =
    #externalMacro(module: "AgentKittenMacros", type: "ToolMacro")

/// Provides a human-readable description for an `Arguments` stored property.
///
/// Read by the ``Tool(_:description:)`` macro when generating the ``ToolSchema``.
/// Expands to nothing on its own — its presence as an annotation is what matters.
///
/// ```swift
/// struct Arguments: Codable, Sendable {
///     @ParameterDescription("City and state, e.g. 'Austin, TX'")
///     let location: String
/// }
/// ```
@attached(peer)
public macro ParameterDescription(_ description: String) =
    #externalMacro(module: "AgentKittenMacros", type: "ParameterDescriptionMacro")
