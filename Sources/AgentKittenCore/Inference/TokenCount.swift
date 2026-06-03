// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// A token count that is either a known non-negative value or unknown.
///
/// Providers that lack a dedicated token-counting endpoint (e.g. OpenAI Chat
/// Completions) may not know the count until after an inference turn completes.
/// `.unknown` carries that signal explicitly rather than encoding it as a
/// sentinel integer.
///
/// ## Ordering
///
/// `.unknown` sorts lower than any `.tokens` value. Comparisons involving
/// `.unknown` on either side return `false` for `>` and `>=`, so unknown usage
/// never spuriously triggers a compaction threshold.
///
/// ## Threshold arithmetic
///
/// The `*` operator scales a token count by a `Double` fraction, returning
/// `.unknown` when the receiver is unknown. This lets compaction triggers
/// be written as:
/// ```swift
/// usage.contextTokens >= usage.contextSize * 0.8
/// ```
public enum TokenCount: Sendable, Equatable, Hashable {
    /// The count is not yet available.
    case unknown
    /// A known count.
    case tokens(UInt)

    // MARK: - Convenience init

    /// Lifts an optional integer into a ``TokenCount``.
    ///
    /// `nil` and negative values both map to `.unknown`.
    public init(_ value: Int?) {
        if let value, value >= 0 {
            self = .tokens(UInt(value))
        } else {
            self = .unknown
        }
    }

    // MARK: - Unwrap

    /// The underlying count, or `nil` when `.unknown`.
    public var value: UInt? {
        if case .tokens(let count) = self { return count }
        return nil
    }
}

// MARK: - Integer literal

extension TokenCount: ExpressibleByIntegerLiteral {
    /// Allows integer literals to be used wherever a `TokenCount` is expected.
    ///
    /// `let threshold: TokenCount = 100` is equivalent to `100`.
    /// Negative literals are rejected at compile time because the underlying
    /// type is `UInt`.
    public typealias IntegerLiteralType = UInt

    public init(integerLiteral value: UInt) {
        self = .tokens(value)
    }
}

// MARK: - Comparable

extension TokenCount: Comparable {
    public static func < (lhs: TokenCount, rhs: TokenCount) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .tokens): true
        case (.tokens(let lhsCount), .tokens(let rhsCount)): lhsCount < rhsCount
        default: false
        }
    }
}

// MARK: - Threshold arithmetic

extension TokenCount {
    /// Returns `.tokens` scaled by `fraction`, or `.unknown` when the receiver is unknown.
    public static func * (lhs: TokenCount, rhs: Double) -> TokenCount {
        guard case .tokens(let count) = lhs else { return .unknown }
        return .tokens(UInt(Double(count) * rhs))
    }
}

// MARK: - Display

extension TokenCount: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown: "unknown"
        case .tokens(let count): "\(count)"
        }
    }
}

// MARK: - Codable

extension TokenCount: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .unknown
        } else {
            self = .tokens(try container.decode(UInt.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unknown:
            try container.encodeNil()
        case .tokens(let count):
            try container.encode(count)
        }
    }
}
