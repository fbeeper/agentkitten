// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore

/// Converts a temperature value between Celsius and Fahrenheit.
///
/// Demonstrates the `@Tool` macro: `name`, `description`, and `schema` are generated
/// at compile time from the struct's annotations. The `TemperatureUnit` enum is a
/// sibling type inside the tool struct; the macro detects its cases and emits
/// `.enumeration(values:)` schema entries for the `from` and `toUnit` parameters.
@Tool("convert_temperature", description: "Converts a temperature value between Celsius (C) and Fahrenheit (F).")
struct ConvertTemperatureTool: AgentTool {
    /// Units supported by the conversion tool. Declared as a sibling type so the
    /// `@Tool` macro can auto-detect the allowed values for schema generation.
    /// No raw-value overrides: the macro and Codable both use the case name as the
    /// string value (`"celsius"` / `"fahrenheit"`), keeping them in sync.
    enum TemperatureUnit: String, Codable, Sendable {
        case celsius
        case fahrenheit
    }

    struct Arguments: Codable, Sendable {
        @ParameterDescription("The temperature value to convert.")
        let value: Double
        @ParameterDescription("The unit to convert from.")
        let from: TemperatureUnit
        @ParameterDescription("The unit to convert to.")
        let toUnit: TemperatureUnit
    }

    struct Output: Codable, Sendable {
        let result: Double
        let formatted: String
    }

    func execute(arguments: Arguments) async throws -> Output {
        let result: Double
        switch (arguments.from, arguments.toUnit) {
        case (.celsius, .fahrenheit):
            result = arguments.value * 9 / 5 + 32
        case (.fahrenheit, .celsius):
            result = (arguments.value - 32) * 5 / 9
        default:
            result = arguments.value
        }
        let unitLabel = arguments.toUnit == .celsius ? "C" : "F"
        let formatted = String(format: "%.1f°%@", result, unitLabel)
        return Output(result: result, formatted: formatted)
    }
}
