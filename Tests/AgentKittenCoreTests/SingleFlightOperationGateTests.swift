// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import AgentKittenCore

private enum TestOperation: Sendable, Equatable {
    case first
    case second
}

private enum TestGateError: Error, Equatable {
    case alreadyRunning(TestOperation)
}

@Test func singleFlightOperationGate_rejectsOverlapAndReportsActiveKind() throws {
    let gate = SingleFlightOperationGate<TestOperation> {
        TestGateError.alreadyRunning($0)
    }
    let lease = try gate.begin(.first)

    #expect(throws: TestGateError.alreadyRunning(.first)) {
        _ = try gate.begin(.second)
    }

    lease.end()
}

@Test func singleFlightOperationGate_allowsNextOperationAfterLeaseEnds() throws {
    let gate = SingleFlightOperationGate<TestOperation> {
        TestGateError.alreadyRunning($0)
    }
    let lease = try gate.begin(.first)
    lease.end()

    let nextLease = try gate.begin(.second)
    nextLease.end()
}

@Test func singleFlightOperationGate_endingLeaseIsIdempotent() throws {
    let gate = SingleFlightOperationGate<TestOperation> {
        TestGateError.alreadyRunning($0)
    }
    let lease = try gate.begin(.first)

    lease.end()
    lease.end()

    let nextLease = try gate.begin(.second)
    nextLease.end()
}
