// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization

/// A reusable single-flight gate keyed by a caller-defined operation kind.
///
/// The gate allows at most one active operation at a time. Callers acquire a
/// ``Lease`` when work starts and must end that lease when the operation is no
/// longer active.
package final class SingleFlightOperationGate<Kind: Sendable>: Sendable {
    private struct ActiveOperation {
        let id: UUID
        let kind: Kind
    }

    private struct State {
        var active: ActiveOperation?
    }

    private let state = Mutex(State())
    private let errorFactory: @Sendable (Kind) -> any Error

    package init(errorFactory: @escaping @Sendable (Kind) -> any Error) {
        self.errorFactory = errorFactory
    }

    package func begin(_ kind: Kind) throws -> Lease {
        let id = UUID()
        let errorFactory = errorFactory
        try state.withLock { state in
            if let active = state.active {
                throw errorFactory(active.kind)
            }
            state.active = ActiveOperation(id: id, kind: kind)
        }
        return Lease(gate: self, operationID: id, operationKind: kind)
    }

    fileprivate func end(operationID: UUID) {
        state.withLock { state in
            guard state.active?.id == operationID else {
                return
            }
            state.active = nil
        }
    }
}

extension SingleFlightOperationGate {
    /// A handle for the currently active operation.
    ///
    /// Ending the same lease multiple times is harmless.
    package final class Lease: Sendable {
        private let gate: SingleFlightOperationGate<Kind>
        private let operationID: UUID
        private let operationKind: Kind
        private let didEnd = Mutex(false)

        fileprivate init(
            gate: SingleFlightOperationGate<Kind>,
            operationID: UUID,
            operationKind: Kind,
        ) {
            self.gate = gate
            self.operationID = operationID
            self.operationKind = operationKind
        }

        package func end() {
            didEnd.withLock { didEnd in
                if didEnd {
                    return
                }
                didEnd = true
                gate.end(operationID: operationID)
            }
        }

        deinit {
            let didEnd = didEnd.withLock { $0 }
            assert(
                didEnd,
                """
                Leaked SingleFlightOperationGate lease for operation kind \(String(describing: operationKind)). \
                Leases must be ended explicitly from the operation lifecycle \
                (for example via defer or stream termination).
                """,
            )
        }
    }
}
