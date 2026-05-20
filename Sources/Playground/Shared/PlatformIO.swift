// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Best-effort flush for interactive Playground CLI output.
/// Uses FileHandle instead of C stdio globals so the helper stays shared across
/// Apple and non-Apple platforms and avoids Swift 6 concurrency diagnostics.
/// Flush failures are ignored because prompt visibility is the only goal here,
/// and the CLI has no meaningful recovery path if synchronization fails.
func flushStdout() {
    try? FileHandle.standardOutput.synchronize()
}

func writeToStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
