// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct ConversationEvent<Result: Sendable>: Sendable {
    let kind: Kind
    let metadata: Metadata
}

extension ConversationEvent: Equatable where Result: Equatable {}
