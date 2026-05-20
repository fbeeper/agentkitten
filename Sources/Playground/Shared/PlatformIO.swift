// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

func flushStdout() {
    try? FileHandle.standardOutput.synchronize()
}

func writeToStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
