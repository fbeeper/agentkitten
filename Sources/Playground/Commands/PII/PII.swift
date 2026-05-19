// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

import AgentKitten
import AgentKittenCore
import ArgumentParser
import Darwin
import Foundation

extension Playground {
    /// Demonstrates PII-safe tool execution via the tool hook chain.
    ///
    /// Emails in user input are replaced with opaque sentinels before the text reaches
    /// the model. A ``ToolHook`` rehydrates the real addresses just before tool execution,
    /// so the model never sees privileged data at any point in the inference loop.
    struct PII: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "PII-safe tool demo: emails are tokenized before reaching the model.",
        )

        @Option(name: .long, help: "Inference provider: anthropic, apple.")
        var provider: ProviderOption = .anthropic

        @Flag(name: .long, help: "Print trace entries (including hook invocations) after each turn.")
        var trace = false

        func run() async throws {
            print(PlaygroundChatOutputFormatter.sessionHeader(
                title: "PII Demo",
                detailLines: [
                    "AgentKitten Playground v\(AgentKitten.version)",
                    "Provider: \(provider.rawValue)",
                    "Emails in input are replaced with sentinels before reaching the model.",
                    "A pre-execution hook rehydrates them just before tool execution.",
                ],
                instructions: "Type a message with an email address, ask the agent to notify them.\nCtrl-D to exit.",
            ))

            let vault = PIIVault()
            let sanitizer = PIIInputSanitizer(vault: vault)
            let rehydrationHook = PIIRehydrationHook(vault: vault)

            let agent = try PlaygroundSessionFactory.makeAgent(
                for: provider,
                behavior: .init(
                    systemPrompt: """
                    You are an assistant that helps send notifications to contacts. \
                    When a user asks to notify or message someone at a given address, \
                    use the notify_contact tool to deliver the message.
                    """,
                ),
                toolDefinition: ToolDefinition(
                    tools: [AnyAgentTool(NotifyContactTool())],
                    hooks: [AnyToolHook(rehydrationHook)],
                ),
            )
            let session = agent.makeSession()
            try await chat(session: session, sanitizer: sanitizer, vault: vault)
            print()
            print("Goodbye!")
        }

        private func chat(session: AgentSession, sanitizer: PIIInputSanitizer, vault: PIIVault) async throws {
            while true {
                print()
                print(PlaygroundChatOutputFormatter.userPrompt())
                fflush(stdout)
                guard let line = readLine(), !line.isEmpty else {
                    break
                }
                let sanitized = await sanitizer.sanitize(line)
                if sanitized != line {
                    print("[sanitized] \(sanitized)")
                }
                let turn = try await session.send(sanitized)
                print()
                print(PlaygroundChatOutputFormatter.assistantHeader(assistantLabel: "Assistant"))
                fflush(stdout)
                do {
                    try await streamTurn(turn, vault: vault)
                } catch {
                    print(PlaygroundChatOutputFormatter.turnError(error))
                }
                if trace {
                    await PlaygroundTracePrinter.printTurnTrace(
                        trace: session.trace,
                        invocationID: turn.id,
                    )
                }
                print(PlaygroundChatOutputFormatter.separator)
            }
        }

        private func streamTurn(_ turn: Turn<AssistantMessage>, vault: PIIVault) async throws {
            var rehydrator = PIIStreamRehydrator()
            for try await event in turn.events {
                switch event.kind {
                case .textDelta(let chunk):
                    let safe = await rehydrator.feed(chunk, vault: vault)
                    if !safe.isEmpty {
                        print(safe, terminator: "")
                        fflush(stdout)
                    }
                case .result:
                    let remaining = await rehydrator.finalize(vault: vault)
                    if !remaining.isEmpty {
                        print(remaining, terminator: "")
                    }
                    print()
                case .toolCallStarted(let name, let id):
                    print("\n[tool:start] \(name) (\(id))", terminator: "")
                    fflush(stdout)
                case .toolApprovalRequired:
                    break
                case .toolCallCompleted(let name, let id, let outcome):
                    switch outcome {
                    case .success:
                        print("\n[tool:done] \(name) (\(id))")
                    case .failure(let failure):
                        print("\n[tool:failed] \(name) (\(id)) \(failure.resultJSON)")
                    }
                    fflush(stdout)
                }
            }
        }
    }
}

// MARK: - PIIStreamRehydrator

/// Rehydrates PII sentinels in a streaming text context.
///
/// Prints text immediately up to any `<` that could start a sentinel, then holds
/// from that point until the sentinel either completes (rehydrate and flush) or
/// is ruled out (flush as-is). Sentinels have the form `<PII:email:N>`.
struct PIIStreamRehydrator {
    private static let sentinelPrefix = "<PII:email:"
    private var held = ""

    /// Feed the next text delta. Returns text that is safe to print immediately.
    mutating func feed(_ chunk: String, vault: PIIVault) async -> String {
        held += chunk
        return await extractSafe(vault: vault)
    }

    /// Flush all remaining held text (call at stream end). Returns the final text to print.
    mutating func finalize(vault: PIIVault) async -> String {
        let result = await vault.rehydrate(held)
        held = ""
        return result
    }

    private mutating func extractSafe(vault: PIIVault) async -> String {
        let prefix = Self.sentinelPrefix
        var output = ""

        while !held.isEmpty {
            guard let ltIdx = held.firstIndex(of: "<") else {
                output += held
                held = ""
                break
            }
            // Flush everything before the `<`.
            output += held[held.startIndex ..< ltIdx]
            held = String(held[ltIdx...])

            if prefix.hasPrefix(held) {
                // held is a valid prefix of the sentinel prefix — hold and wait for more.
                break
            }
            if held.hasPrefix(prefix) {
                // Past the prefix — accumulating the digit + closing `>`.
                let digits = held.dropFirst(prefix.count)
                if let gtIdx = digits.firstIndex(of: ">") {
                    // Complete sentinel.
                    let sentinel = String(held[held.startIndex ... gtIdx])
                    // Rehydrate via the vault; falls back to the original if unknown.
                    output += await vault.rehydrate(sentinel)
                    held = String(held.dropFirst(sentinel.count))
                } else if digits.allSatisfy(\.isNumber) {
                    // Digits so far but no `>` yet — hold and wait.
                    break
                } else {
                    // Not a valid sentinel — flush the `<` and re-scan the rest.
                    output += "<"
                    held = String(held.dropFirst())
                }
            } else {
                // `<` followed by something that can't start our sentinel — flush it.
                output += "<"
                held = String(held.dropFirst())
            }
        }
        return output
    }
}

// MARK: - NotifyContactTool

private struct NotifyContactTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let email: String
        let message: String
    }

    struct Output: Codable, Sendable {
        let notified: Bool
        let recipient: String
    }

    static let name = "notify_contact"
    static let defaultDescription = "Sends a notification message to a contact's email address."

    var schema: ToolSchema {
        ToolSchema(parameters: .object(
            properties: [
                "email": .string(description: "The recipient's email address."),
                "message": .string(description: "The message body to send."),
            ],
            required: ["email", "message"],
        ))
    }

    func execute(arguments: Arguments) async throws -> Output {
        Output(notified: true, recipient: arguments.email)
    }
}

// MARK: - PIIVault

actor PIIVault {
    private var emailMap: [String: String] = [:]

    /// Stores an email and returns its sentinel token.
    func store(email: String) -> String {
        if let existing = emailMap.first(where: { $0.value == email })?.key {
            return existing
        }
        let sentinel = "<PII:email:\(emailMap.count)>"
        emailMap[sentinel] = email
        return sentinel
    }

    /// Replaces known emails with their sentinel tokens (redaction direction).
    func sanitize(_ text: String) -> String {
        var result = text
        for (sentinel, email) in emailMap {
            result = result.replacingOccurrences(of: email, with: sentinel)
        }
        return result
    }

    /// Replaces all sentinels in `text` with the stored email addresses (rehydration direction).
    func rehydrate(_ text: String) -> String {
        var result = text
        for (sentinel, email) in emailMap {
            result = result.replacingOccurrences(of: sentinel, with: email)
        }
        return result
    }
}

// MARK: - PIIInputSanitizer

struct PIIInputSanitizer {
    private let vault: PIIVault
    // swiftlint:disable:next force_try
    private let emailRegex = try! NSRegularExpression(
        pattern: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#,
    )

    init(vault: PIIVault) {
        self.vault = vault
    }

    /// Returns input with email addresses replaced by opaque sentinel tokens.
    func sanitize(_ input: String) async -> String {
        let nsInput = input as NSString
        let range = NSRange(location: 0, length: nsInput.length)
        let matches = emailRegex.matches(in: input, range: range)
        guard !matches.isEmpty else {
            return input
        }
        var seen = Set<String>()
        var emails = [String]()
        for match in matches {
            let email = nsInput.substring(with: match.range)
            if seen.insert(email).inserted {
                emails.append(email)
            }
        }
        var result = input
        for email in emails {
            let sentinel = await vault.store(email: email)
            result = result.replacingOccurrences(of: email, with: sentinel)
        }
        return result
    }
}

// MARK: - PIIRehydrationHook

struct PIIRehydrationHook: ToolHook {
    let name = "PIIRehydration"
    let phases: Set<ToolHookPhase> = [.before, .after]

    private let vault: PIIVault

    init(vault: PIIVault) {
        self.vault = vault
    }

    func beforeExecute(
        _ call: PendingToolCall,
        context: ToolExecutionContext,
    ) async throws -> PendingToolCall {
        let rehydrated = await vault.rehydrate(call.argumentsJSON)
        guard rehydrated != call.argumentsJSON else {
            return call
        }
        return PendingToolCall(
            id: call.id,
            name: call.name,
            argumentsJSON: rehydrated,
            modelRationale: call.modelRationale,
        )
    }

    func afterExecute(
        _ call: PendingToolCall,
        outcome: ToolCallOutcome,
        context: ToolExecutionContext,
    ) async -> ToolCallOutcome {
        guard case .success(let content) = outcome else {
            return outcome
        }
        var redacted = [ToolResultContent]()
        for item in content {
            if case .text(let text) = item {
                redacted.append(.text(await vault.sanitize(text)))
            } else {
                redacted.append(item)
            }
        }
        return .success(content: redacted)
    }
}
