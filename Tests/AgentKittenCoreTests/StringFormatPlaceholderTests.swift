// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

@testable import AgentKittenCore
import Testing

@Suite("String Format Placeholder")
struct StringFormatPlaceholderTests {
    @Test func formatPlaceholderCount_countsObjectPlaceholders() {
        #expect("%@".formatPlaceholderCount == 1)
        #expect("%1$@ %2$@".formatPlaceholderCount == 2)
        #expect("prefix %@ middle %3$@ suffix".formatPlaceholderCount == 2)
        #expect("no object placeholders here".formatPlaceholderCount == 0)
    }

    @Test func formatPlaceholderCount_misclassifiesEscapedPercentAtKnownIssue() {
        withKnownIssue("Escaped %%@ is currently misclassified as an object placeholder.") {
            #expect("%%@".formatPlaceholderCount == 0)
        }
    }
}
