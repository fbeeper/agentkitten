// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import AgentKittenCore
@testable import AgentKittenOpenAIInference
import Foundation
import Testing

@Suite("OpenAI tool result encoding")
struct OpenAIToolResultEncodingTests {
    @Test("encodes text-only tool result as string content")
    func textOnlyToolResultEncodesStringContent() throws {
        let message = OpenAIMessage.toolResult(
            toolCallID: "call-1",
            content: [.text("hello")],
            isError: false,
        )

        let object = try encodedObject(message)

        #expect(object["role"] as? String == "tool")
        #expect(object["tool_call_id"] as? String == "call-1")
        #expect(object["content"] as? String == "hello")
    }

    @Test("encodes image-only tool result as string placeholder")
    func imageOnlyToolResultEncodesStringPlaceholder() throws {
        let message = OpenAIMessage.toolResult(
            toolCallID: "call-1",
            content: [.image(mediaType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))],
            isError: false,
        )

        let object = try encodedObject(message)

        #expect(object["content"] as? String == "[Image omitted: image/png, 4 bytes]")
        #expect(try encodedString(message).contains("image_url") == false)
    }

    @Test("encodes mixed text and image tool result as one string")
    func mixedToolResultEncodesStringContent() throws {
        let message = OpenAIMessage.toolResult(
            toolCallID: "call-1",
            content: [
                .text("first"),
                .image(mediaType: "image/png", data: Data([0x89])),
                .text("last"),
            ],
            isError: false,
        )

        let object = try encodedObject(message)

        #expect(object["content"] as? String == "first\n[Image omitted: image/png, 1 bytes]\nlast")
        #expect(object["content"] is [[String: Any]] == false)
    }

    @Test("encodes error tool result with error prefix")
    func errorToolResultEncodesErrorPrefix() throws {
        let message = OpenAIMessage.toolResult(
            toolCallID: "call-1",
            content: [
                .text("failed"),
                .image(mediaType: "image/png", data: Data([0x89])),
            ],
            isError: true,
        )

        let object = try encodedObject(message)

        #expect(object["content"] as? String == "[Error] failed\n[Image omitted: image/png, 1 bytes]")
    }

    private func encodedObject(_ message: OpenAIMessage) throws -> [String: Any] {
        let data = try JSONEncoder().encode(message)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encodedString(_ message: OpenAIMessage) throws -> String {
        let data = try JSONEncoder().encode(message)
        return try #require(String(data: data, encoding: .utf8))
    }
}

#endif
