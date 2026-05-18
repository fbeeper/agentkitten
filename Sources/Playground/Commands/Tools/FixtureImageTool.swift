// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKittenCore
import Foundation

/// Returns a bundled demo PNG as rich tool result content.
///
/// The bundled fixture must be present at `Sources/Playground/Fixtures/rich-tool-demo.png`.
struct FixtureImageTool: RichAgentTool {
    struct Arguments: Codable, Sendable {}

    static let name = "fixture_image"
    static let description = """
    Returns a bundled demo PNG as an image tool result. Use this when you need to inspect \
    the image directly rather than infer from text alone.
    """

    var schema: ToolSchema {
        ToolSchema(parameters: .object(properties: [:], required: []))
    }

    var capabilities: ToolCapabilities {
        ToolCapabilities(toolResultContentKinds: [.text, .image])
    }

    func execute(arguments: Arguments) async throws -> [ToolResultContent] {
        let url = try fixtureURL()
        let data = try Data(contentsOf: url)
        return [
            .text("Bundled demo image attached."),
            .image(mediaType: "image/png", data: data),
        ]
    }

    private func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "rich-tool-demo", withExtension: "png") else {
            throw FixtureImageToolError.missingFixture(
                "Missing bundled fixture rich-tool-demo.png in Sources/Playground/Fixtures.",
            )
        }
        return url
    }
}

private enum FixtureImageToolError: LocalizedError {
    case missingFixture(String)

    var errorDescription: String? {
        switch self {
        case .missingFixture(let message):
            message
        }
    }
}
