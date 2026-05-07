// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import AgentKittenCore

@Suite("AgentKitten Localization", .serialized)
struct AgentKittenLocalizationTests {

    @Test func overrideBundle_beatsPackagedDefault() async throws {
        let saved = AgentKittenLocalization.overrideBundle
        defer { AgentKittenLocalization.overrideBundle = saved }

        AgentKittenLocalization.overrideBundle = Bundle.module
        let result = AgentKittenLocalization.string("tools.guidancePrompt")
        #expect(result == "TEST BUNDLE TOOL GUIDANCE")
    }

    @Test func overrideBundle_beatsPackagedDefaultForValidationMessage() throws {
        let saved = AgentKittenLocalization.overrideBundle
        defer { AgentKittenLocalization.overrideBundle = saved }

        AgentKittenLocalization.overrideBundle = Bundle.module
        let result = AgentKittenLocalization.string("validation.validationPassed")
        #expect(result == "VALIDATION FROM TEST BUNDLE")
    }

}
