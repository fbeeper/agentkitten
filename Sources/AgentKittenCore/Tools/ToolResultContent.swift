// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A provider-neutral content block produced by a tool invocation.
public enum ToolResultContent: Sendable, Equatable, Hashable {
    /// Plain text content.
    case text(String)
    /// Binary image content.
    case image(mediaType: String, data: Data)

    /// A lightweight summary suitable for trace storage.
    public var summary: ToolResultContentSummary {
        switch self {
        case .text(let text):
            .text(text)
        case .image(let mediaType, let data):
            .image(mediaType: mediaType, byteCount: data.count)
        }
    }

    /// The capability kind represented by this content block.
    public var kind: ToolResultContentKind {
        switch self {
        case .text:
            .text
        case .image:
            .image
        }
    }
}

/// The kinds of tool result content a tool may emit.
public enum ToolResultContentKind: String, Sendable, Codable, Hashable {
    /// Plain text content.
    case text
    /// Binary image content.
    case image
}

/// A lossy trace-safe summary of a tool result block.
public enum ToolResultContentSummary: Sendable, Codable, Equatable, Hashable {
    /// Plain text content.
    case text(String)
    /// Image metadata without raw bytes.
    case image(mediaType: String, byteCount: Int)
}
