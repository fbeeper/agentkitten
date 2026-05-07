// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

// MARK: - UserIDTests

@Suite struct UserIDTests {

    @Test func construction_andDescription() {
        let id: UserID = "alice"
        #expect(id.description == "alice")
    }

    @Test func stringLiteral() {
        let id: UserID = "alice"
        #expect(id == "alice")
    }

    @Test func equality_sameValue() {
        #expect(("alice" as UserID) == "alice")
    }

    @Test func equality_differentValue() {
        #expect(("alice" as UserID) != "bob")
    }

    @Test func hashEquality_sameValue() {
        var set = Set<UserID>()
        set.insert("alice")
        set.insert("alice")
        #expect(set.count == 1)
    }

    @Test func codableRoundTrip() throws {
        let original: UserID = "alice"
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserID.self, from: data)
        #expect(original == decoded)
    }

    @Test func codableJSON_isPlainString() throws {
        let data = try JSONEncoder().encode("alice" as UserID)
        let json = try JSONDecoder().decode(String.self, from: data)
        #expect(json == "alice")
    }

    @Test func local_expectedString() {
        #expect(UserID.local.description == "_local")
    }

    @Test func local_stable() {
        #expect(UserID.local == UserID.local)
    }

}

// MARK: - AgentIDTests

@Suite struct AgentIDTests {

    @Test func construction_andDescription() {
        let id: AgentID = "weatherAgent"
        #expect(id.description == "weatherAgent")
    }

    @Test func stringLiteral() {
        let id: AgentID = "weatherAgent"
        #expect(id == "weatherAgent")
    }

    @Test func equality_sameValue() {
        #expect(("weatherAgent" as AgentID) == "weatherAgent")
    }

    @Test func equality_differentValue() {
        #expect(("weatherAgent" as AgentID) != "calendarAgent")
    }

    @Test func hashEquality_sameValue() {
        var set = Set<AgentID>()
        set.insert("weatherAgent")
        set.insert("weatherAgent")
        #expect(set.count == 1)
    }

    @Test func codableRoundTrip() throws {
        let original: AgentID = "weatherAgent"
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentID.self, from: data)
        #expect(original == decoded)
    }

    @Test func codableJSON_isPlainString() throws {
        let data = try JSONEncoder().encode("weatherAgent" as AgentID)
        let json = try JSONDecoder().decode(String.self, from: data)
        #expect(json == "weatherAgent")
    }

    @Test func generate_nonEmpty() {
        #expect(!AgentID.generate().description.isEmpty)
    }

    @Test func generate_uniqueness() {
        #expect(AgentID.generate() != AgentID.generate())
    }

    // Type-safety note: UserID and AgentID are distinct structs.
    // The following would not compile:
    //   let u: UserID = ("x" as AgentID)  // compiler error — intentional
}

// MARK: - SessionIDTests

@Suite struct SessionIDTests {

    @Test func generate_nonEmpty() {
        #expect(!AgentSessionID.generate().description.isEmpty)
    }

    @Test func generate_uniqueness() {
        #expect(AgentSessionID.generate() != AgentSessionID.generate())
    }

    @Test func codableRoundTrip() throws {
        let original = AgentSessionID.generate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentSessionID.self, from: data)
        #expect(original == decoded)
    }

    @Test func codableJSON_isPlainString() throws {
        let id = AgentSessionID.generate()
        let data = try JSONEncoder().encode(id)
        let json = try JSONDecoder().decode(String.self, from: data)
        #expect(json == id.description)
    }

    @Test func hashEquality_afterCodableRoundTrip() throws {
        let original = AgentSessionID.generate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentSessionID.self, from: data)
        var set = Set<AgentSessionID>()
        set.insert(original)
        set.insert(decoded)
        #expect(set.count == 1)
    }
}

// MARK: - InvocationIDTests

@Suite struct InvocationIDTests {

    @Test func generate_nonEmpty() {
        #expect(!InvocationID.generate().description.isEmpty)
    }

    @Test func generate_uniqueness() {
        #expect(InvocationID.generate() != InvocationID.generate())
    }

    @Test func codableRoundTrip() throws {
        let original = InvocationID.generate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InvocationID.self, from: data)
        #expect(original == decoded)
    }

    @Test func codableJSON_isPlainString() throws {
        let id = InvocationID.generate()
        let data = try JSONEncoder().encode(id)
        let json = try JSONDecoder().decode(String.self, from: data)
        #expect(json == id.description)
    }

    @Test func hashEquality_afterCodableRoundTrip() throws {
        let original = InvocationID.generate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InvocationID.self, from: data)
        var set = Set<InvocationID>()
        set.insert(original)
        set.insert(decoded)
        #expect(set.count == 1)
    }

    // Type-safety note: InvocationID is a distinct struct; ToolCallID is typealias = String.
    // Passing an InvocationID where ToolCallID (String) is expected is a compiler error — intentional.
}

// MARK: - EventIDTests

@Suite struct EventIDTests {

    @Test func generate_nonEmpty() {
        #expect(!EventID.generate().description.isEmpty)
    }

    @Test func generate_uniqueness() {
        #expect(EventID.generate() != EventID.generate())
    }

    @Test func codableRoundTrip() throws {
        let original = EventID.generate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventID.self, from: data)
        #expect(original == decoded)
    }

    @Test func codableJSON_isPlainString() throws {
        let id = EventID.generate()
        let data = try JSONEncoder().encode(id)
        let json = try JSONDecoder().decode(String.self, from: data)
        #expect(json == id.description)
    }

    @Test func hashEquality_afterCodableRoundTrip() throws {
        let original = EventID.generate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventID.self, from: data)
        var set = Set<EventID>()
        set.insert(original)
        set.insert(decoded)
        #expect(set.count == 1)
    }
}
