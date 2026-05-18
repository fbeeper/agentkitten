// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Foundation
import Testing

@Suite("AgentKitten Localization", .serialized)
struct AgentKittenLocalizationTests {
    @Test func overrideBundle_beatsPackagedDefault() {
        let saved = AgentKittenLocalization.overrideBundle
        defer { AgentKittenLocalization.overrideBundle = saved }

        AgentKittenLocalization.overrideBundle = Bundle.module
        let result = AgentKittenLocalization.string("tools.guidancePrompt")
        #expect(result == "TEST BUNDLE TOOL GUIDANCE")
    }

    @Test func overrideBundle_beatsPackagedDefaultForValidationMessage() {
        let saved = AgentKittenLocalization.overrideBundle
        defer { AgentKittenLocalization.overrideBundle = saved }

        AgentKittenLocalization.overrideBundle = Bundle.module
        let result = AgentKittenLocalization.string("validation.validationPassed")
        #expect(result == "VALIDATION FROM TEST BUNDLE")
    }
}
