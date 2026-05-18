// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A session-state value.
///
/// Session state currently stores plain strings only.
public typealias SessionStateValue = String

/// Error raised when a session-state mutation is not permitted.
public enum SessionStateError: Error, LocalizedError, Equatable {
    /// The session state is disabled and cannot be mutated.
    case disabled
    /// The session state is read-only and cannot be mutated.
    case readOnlyMutation

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "Session state is disabled."
        case .readOnlyMutation:
            return "Session state is read-only."
        }
    }
}

/// Mutable, session-scoped scratchpad storage for one ``AgentSession``.
///
/// Session state is ephemeral and belongs to a single runtime session. Values
/// survive across turns within that session and disappear when the session is
/// released.
public actor SessionState {
    enum Access: Sendable, Equatable {
        case readWrite
        case readOnly
    }

    private let trace: AgentTrace
    private let access: Access
    private var storage: [String: SessionStateValue] = [:]
    private var activeInvocationID: InvocationID?

    init(
        trace: AgentTrace,
        contents: [String: SessionStateValue] = [:],
        access: Access = .readWrite,
    ) {
        self.trace = trace
        self.storage = contents
        self.access = access
    }

    /// Creates a read-only state instance with explicit immutable intent.
    ///
    /// This sits alongside the internal initializer as a named constructor so
    /// call sites do not have to spell the raw access enum when they mean
    /// “make an immutable copy”.
    static func readOnly(
        trace: AgentTrace,
        contents: [String: SessionStateValue],
    ) -> SessionState {
        SessionState(
            trace: trace,
            contents: contents,
            access: .readOnly,
        )
    }

    /// Returns the value currently stored under `key`, or `nil` if absent.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The stored value, if present.
    public func value(forKey key: String) -> SessionStateValue? {
        storage[key]
    }

    func contents() -> [String: SessionStateValue] {
        storage
    }

    /// Stores or replaces the value under `key`.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - key: The key to update.
    public func setValue(_ value: SessionStateValue, forKey key: String) async throws {
        try ensureWritable()
        storage[key] = value
        recordMutation(
            .set,
            key: key,
            valueType: "string",
        )
    }

    /// Removes the value under `key`.
    ///
    /// - Parameter key: The key to remove.
    /// - Returns: `true` when a value existed and was removed.
    @discardableResult
    public func removeValue(forKey key: String) async throws -> Bool {
        try ensureWritable()
        guard storage.removeValue(forKey: key) != nil else {
            return false
        }
        recordMutation(.remove, key: key, valueType: nil)
        return true
    }

    /// Removes every value currently stored in this session state.
    ///
    /// - Returns: The keys that were removed, sorted for deterministic reporting.
    @discardableResult
    public func clear() async throws -> [String] {
        try ensureWritable()
        let keys = storage.keys.sorted()
        storage.removeAll()
        for key in keys {
            recordMutation(.remove, key: key, valueType: nil)
        }
        return keys
    }

    func beginTurn(invocationID: InvocationID) {
        activeInvocationID = invocationID
    }

    func endTurn() {
        activeInvocationID = nil
    }

    private func ensureWritable() throws {
        guard access == .readWrite else {
            throw SessionStateError.readOnlyMutation
        }
    }

    private func recordMutation(
        _ operation: AgentTraceEntry.Kind.StateMutation.Operation,
        key: String,
        valueType: String?,
    ) {
        guard let activeInvocationID else {
            return
        }
        trace.append(
            kind: .stateMutation(.init(
                operation: operation,
                key: key,
                valueType: valueType,
            )),
            invocationID: activeInvocationID,
        )
    }
}
