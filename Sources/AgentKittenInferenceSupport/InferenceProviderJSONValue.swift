// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A recursive JSON value used for encoding and decoding tool schemas and inputs.
///
/// Serializes to and from the flat JSON format that inference provider APIs expect
/// (e.g., `"type": "string"` rather than a Swift enum case).
///
/// Use ``InferenceProviderJSONValue/encoding(_:)`` to convert a ``JSONSchema`` to a ``InferenceProviderJSONValue``
/// for inclusion in an API request.
package enum InferenceProviderJSONValue: Codable, Equatable, Sendable {
    indirect case object([String: InferenceProviderJSONValue])
    indirect case array([InferenceProviderJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .object(let dict):
            var container = encoder.container(keyedBy: StringKey.self)
            for (key, value) in dict {
                try container.encode(value, forKey: StringKey(key))
            }
        case .array(let arr):
            var container = encoder.unkeyedContainer()
            for item in arr {
                try container.encode(item)
            }
        case .string(let str):
            var container = encoder.singleValueContainer()
            try container.encode(str)
        case .number(let num):
            var container = encoder.singleValueContainer()
            try container.encode(num)
        case .bool(let flag):
            var container = encoder.singleValueContainer()
            try container.encode(flag)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([InferenceProviderJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: InferenceProviderJSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    private struct StringKey: CodingKey {
        var stringValue: String

        var intValue: Int? {
            nil
        }

        init(_ string: String) {
            stringValue = string
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}
