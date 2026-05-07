// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

/// Terminal outcome recorded for one agent turn.
extension AgentTraceEntry.Kind {
    public enum TurnOutcome: Sendable, Codable, Equatable, Hashable {
        /// The turn completed successfully.
        case completed
        /// The turn was cancelled before completion.
        case cancelled
        /// The turn failed with an error.
        case failed(ErrorInfo)

        private enum CodingKeys: String, CodingKey {
            case type
            case error
        }

        private enum CaseKind: String, Codable {
            case completed
            case cancelled
            case failed
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(CaseKind.self, forKey: .type) {
            case .completed:
                self = .completed
            case .cancelled:
                self = .cancelled
            case .failed:
                self = .failed(try container.decode(ErrorInfo.self, forKey: .error))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .completed:
                try container.encode(CaseKind.completed, forKey: .type)
            case .cancelled:
                try container.encode(CaseKind.cancelled, forKey: .type)
            case .failed(let error):
                try container.encode(CaseKind.failed, forKey: .type)
                try container.encode(error, forKey: .error)
            }
        }
    }
}
