// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AgentSession {
    func record(
        kind: AgentTraceEntry.Kind,
        invocationID: InvocationID,
    ) {
        trace.append(
            kind: kind,
            invocationID: invocationID,
        )
    }
}
