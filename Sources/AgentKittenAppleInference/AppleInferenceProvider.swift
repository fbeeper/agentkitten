// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(FoundationModels)
import AgentKittenCore
import AgentKittenInferenceSupport
import FoundationModels

/// Selects the Apple on-device language model for agent sessions.
///
/// `SystemLanguageModel.UseCase` is `Equatable` but not `Hashable`, so AgentKitten
/// defines this thin wrapper that satisfies the ``ExecutionConfigurationKey``
/// `Value: Hashable` requirement and maps to the framework type at call sites.
///
/// Set this key on ``AgentBehavior`` or ``TurnOverrides`` to override the
/// default model for a session:
///
/// ```swift
/// var behavior = AgentBehavior(systemPrompt: "You are a helpful assistant.")
/// behavior.phaseBehaviors.base[AppleLanguageModelKey.self] = .contentTagging
/// ```
@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
public enum AppleLanguageModel: Sendable, Hashable {
    /// The default system language model (`SystemLanguageModel.default`).
    case `default`
    /// A model optimised for content tagging (`SystemLanguageModel.UseCase.contentTagging`).
    case contentTagging
}

@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
extension AppleLanguageModel {
    var systemLanguageModel: SystemLanguageModel {
        switch self {
        case .default:
            SystemLanguageModel.default
        case .contentTagging:
            SystemLanguageModel(useCase: .contentTagging)
        }
    }
}

/// Overrides the Apple language model for a session.
///
/// Changing this value between turns triggers ``SessionCompatibility/rebuildSession``
/// so the new model takes effect while preserving conversation history.
@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
public struct AppleLanguageModelKey: ExecutionConfigurationKey {
    public typealias Value = AppleLanguageModel
    public static let domains: Set<ExecutionConfigurationDomain> = [.inference]
}

/// An `InferenceProviding` conformer backed by Apple's on-device Foundation Models framework.
///
/// Requires Foundation Models support on macOS 26+, iOS 26+, visionOS 26+, or
/// macCatalyst 26+. All inference runs locally — no data leaves the device.
/// Each ``Conversation`` gets one ``AppleInferenceSession`` which holds a
/// `LanguageModelSession` for its lifetime, preserving turn history automatically.
@available(macOS 26, iOS 26, visionOS 26, macCatalyst 26, *)
public actor AppleInferenceProvider: InferenceProviding {
    /// The model used when no ``AppleLanguageModelKey`` is set on a turn or behavior.
    public let defaultModel: AppleLanguageModel
    private let historyRenderingConfiguration: HistoryRenderingConfiguration

    /// Creates a new Apple inference provider.
    ///
    /// - Parameters:
    ///   - defaultModel: The model to use when no ``AppleLanguageModelKey`` override
    ///     is present. Defaults to ``AppleLanguageModel/default``.
    ///   - historyRenderingConfiguration: Labels and format strings used when rendering history
    ///     during context compaction. Defaults to built-in English values.
    public init(
        defaultModel: AppleLanguageModel = .default,
        historyRenderingConfiguration: HistoryRenderingConfiguration = HistoryRenderingConfiguration(),
    ) {
        self.defaultModel = defaultModel
        self.historyRenderingConfiguration = historyRenderingConfiguration
    }

    public nonisolated func preflight(
        toolRegistry: ToolRegistry,
        toolSelection: ToolSelection,
    ) throws {
        if let error = AppleToolResultSupport.unsupportedToolError(
            for: toolRegistry.filtered(by: toolSelection),
        ) {
            throw error
        }
    }

    /// Returns ``SessionCompatibility/rebuildSession`` when `toolSelection` or the language
    /// model changes.
    ///
    /// Apple applies tool availability and model selection at session construction time, so
    /// AgentKitten rebuilds the session when either changes. The rebuild preserves conversation
    /// history via `LanguageModelSession.transcript`.
    public nonisolated func sessionCompatibility(
        from current: EffectiveExecutionConfiguration,
        to next: EffectiveExecutionConfiguration,
    ) -> SessionCompatibility {
        if current.provider != next.provider {
            return .replace
        }
        let modelChanged = current.inferenceContext[AppleLanguageModelKey.self]
            != next.inferenceContext[AppleLanguageModelKey.self]
        if current.toolSelection != next.toolSelection || modelChanged {
            return .rebuildSession
        }
        return .reuse
    }

    /// Creates a new Apple session for a single conversation thread.
    ///
    /// Tools are bridged from `toolRuntime` filtered by `toolSelection`. The language model
    /// is determined by ``AppleLanguageModelKey`` in `inferenceContext`; defaults to
    /// ``AppleLanguageModel/default`` when absent.
    public nonisolated func makeSession(
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) -> AppleInferenceSession {
        let model = (inferenceContext[AppleLanguageModelKey.self] ?? defaultModel).systemLanguageModel
        return AppleInferenceSession(
            systemPrompt: systemPrompt,
            model: model,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            historyRenderingConfiguration: historyRenderingConfiguration,
        )
    }

    /// Creates a new Apple session that continues from `session`'s transcript.
    ///
    /// The prior session's turn history is preserved via `LanguageModelSession.transcript`.
    /// Tools are rebound to the new ``ToolRuntime`` and gated by `toolSelection`. The system
    /// prompt is carried forward within the transcript itself; Foundation Models does not
    /// accept a separate `instructions:` argument on transcript-based session construction.
    public func makeSession(
        continuing session: AppleInferenceSession,
        systemPrompt: String?,
        toolRuntime: ToolRuntime,
        toolSelection: ToolSelection,
        inferenceContext: InferenceContext,
    ) async throws -> AppleInferenceSession {
        let transcript: FoundationModels.Transcript = await session.captureTranscript()
        let model = (inferenceContext[AppleLanguageModelKey.self] ?? defaultModel).systemLanguageModel
        return AppleInferenceSession(
            transcript: transcript,
            model: model,
            toolRuntime: toolRuntime,
            toolSelection: toolSelection,
            historyRenderingConfiguration: historyRenderingConfiguration,
        )
    }
}
#endif
