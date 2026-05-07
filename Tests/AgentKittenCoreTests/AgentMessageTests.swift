// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

@Test func userMessage_codableRoundTrip() throws {
    let original = AgentMessage.user(UserMessage(text: "Hello", sender: "alice"))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AgentMessage.self, from: data)
    #expect(original == decoded)
}

@Test func userMessage_codableRoundTrip_defaultSender() throws {
    // UserMessages encoded before sender was introduced (no "sender" field) decode as .local.
    let legacyJSON = #"{"text":"Hello"}"#
    let data = try #require(legacyJSON.data(using: .utf8))
    let decoded = try JSONDecoder().decode(UserMessage.self, from: data)
    #expect(decoded == UserMessage(text: "Hello", sender: .local))
}

@Test func userMessage_sender_roundTrip() throws {
    let msg = UserMessage(text: "Hi", sender: "alice")
    let data = try JSONEncoder().encode(msg)
    let decoded = try JSONDecoder().decode(UserMessage.self, from: data)
    #expect(decoded.sender == "alice")
}

@Test func assistantMessage_codableRoundTrip() throws {
    let original = AgentMessage.assistant(AssistantMessage(text: "Hi there"))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AgentMessage.self, from: data)
    #expect(original == decoded)
}

@Test func systemMessage_codableRoundTrip() throws {
    let original = AgentMessage.system(SystemMessage(text: "Be concise."))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AgentMessage.self, from: data)
    #expect(original == decoded)
}
