// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

@Suite("AgentTrace Queue")
struct TraceQueueTests {
    @Test func snapshotFlushesQueuedAppends() async {
        let trace = AgentTrace(retentionPolicy: .unbounded)
        let invocationID = InvocationID.generate()

        trace.append(
            kind: .turnStarted(UserMessage(text: "Hello")),
            invocationID: invocationID,
        )

        let eventualEntries = await trace.entries
        let snapshot = await trace.snapshot()

        #expect(eventualEntries.count <= snapshot.count)
        #expect(snapshot.map(\.kind) == [
            .turnStarted(UserMessage(text: "Hello")),
        ])
    }

    @Test func sequentialAppendsAreAppliedFIFO() async {
        let trace = AgentTrace(retentionPolicy: .unbounded)
        let invocationID = InvocationID.generate()

        trace.append(
            kind: .turnStarted(UserMessage(text: "Hello")),
            invocationID: invocationID,
        )
        trace.append(
            kind: .message(.assistant(AssistantMessage(text: "One"))),
            invocationID: invocationID,
        )
        trace.append(
            kind: .turnCompleted(.completed),
            invocationID: invocationID,
        )

        #expect((await trace.snapshot()).map(\.kind) == [
            .turnStarted(UserMessage(text: "Hello")),
            .message(.assistant(AssistantMessage(text: "One"))),
            .turnCompleted(.completed),
        ])
    }

    @Test func concurrentAppendsRetainArrivalOrderedEntries() async {
        let trace = AgentTrace(retentionPolicy: .unbounded)
        let invocationID = InvocationID.generate()
        let messages = (0 ..< 20).map { "message-\($0)" }

        await withTaskGroup(of: Void.self) { group in
            for message in messages {
                group.addTask {
                    trace.append(
                        kind: .message(.assistant(AssistantMessage(text: message))),
                        invocationID: invocationID,
                    )
                }
            }
        }

        let snapshot = await trace.snapshot()
        let received = snapshot.compactMap { entry -> String? in
            guard case .message(.assistant(let message)) = entry.kind else {
                return nil
            }
            return message.text
        }

        #expect(Set(received) == Set(messages))
        #expect(received.count == messages.count)
    }

    @Test func observerRegistrationDoesNotReplayOlderQueuedEntries() async {
        let trace = AgentTrace(retentionPolicy: .unbounded)
        let invocationID = InvocationID.generate()

        trace.append(
            kind: .message(.assistant(AssistantMessage(text: "before"))),
            invocationID: invocationID,
        )

        let stream = trace.observe()
        let streamTask = Task<AgentTraceEntry?, Never> {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        trace.append(
            kind: .message(.assistant(AssistantMessage(text: "after"))),
            invocationID: invocationID,
        )

        let entry = await streamTask.value
        #expect(entry?.kind == .message(.assistant(AssistantMessage(text: "after"))))
        #expect((await trace.snapshot()).map(\.kind) == [
            .message(.assistant(AssistantMessage(text: "before"))),
            .message(.assistant(AssistantMessage(text: "after"))),
        ])
    }

    @Test func timestampsReconstructDatesFromTraceAnchor() async {
        let trace = AgentTrace(retentionPolicy: .unbounded)
        let invocationID = InvocationID.generate()

        trace.append(
            kind: .message(.assistant(AssistantMessage(text: "first"))),
            invocationID: invocationID,
        )
        trace.append(
            kind: .message(.assistant(AssistantMessage(text: "second"))),
            invocationID: invocationID,
        )

        let timestamps = await trace.snapshot().map(\.timestamp)
        let dates = timestamps.map { $0.date(anchoredAt: trace.timestampAnchor) }
        #expect(timestamps.count == 2)
        #expect(timestamps[0] <= timestamps[1])
        #expect(trace.timestampAnchor.date <= dates[0])
        #expect(dates[0] <= dates[1])
    }

    @Test func timestampCapturesDateAndInstant() throws {
        let timestamp = AgentTraceEntry.Timestamp()
        let entry = AgentTraceEntry(
            kind: .turnCompleted(.completed),
            timestamp: timestamp,
            invocationID: .generate(),
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AgentTraceEntry.self, from: data)
        let timestampSet: Set<AgentTraceEntry.Timestamp> = [
            timestamp,
            decoded.timestamp,
        ]

        #expect(decoded == entry)
        #expect(timestampSet.count == 1)
    }

    @Test func traceAnchorConvertsEntryTimestampToDate() async throws {
        let trace = AgentTrace(retentionPolicy: .unbounded)
        let invocationID = InvocationID.generate()

        trace.append(
            kind: .message(.assistant(AssistantMessage(text: "anchored"))),
            invocationID: invocationID,
        )

        let entry = try #require(await trace.snapshot().first)
        let anchoredDate = entry.timestamp.date(anchoredAt: trace.timestampAnchor)

        #expect(anchoredDate >= trace.timestampAnchor.date)
    }
}
