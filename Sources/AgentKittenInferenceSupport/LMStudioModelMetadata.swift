// SPDX-FileCopyrightText: 2026 AgentKitten Authors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin) || canImport(FoundationNetworking)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Best-effort probe of LM Studio's native model-metadata endpoint.
///
/// LM Studio serves both OpenAI-compatible (`/v1/chat/completions`) and Anthropic-compatible
/// (`/v1/messages`) chat APIs, but neither reports the model context window on the standard
/// `/models/{id}` route. Its native REST API does: `GET /api/v1/models` lists every model with
/// its served context window.
///
/// Both the OpenAI and Anthropic providers use this to discover the window when pointed at a
/// local LM Studio server, gated behind an opt-in flag. The probe is unauthenticated and
/// provider-neutral; it derives the native endpoint from the provider base URL.
package enum LMStudioModelMetadata {
    /// Returns the served context window for `model` from LM Studio's native metadata endpoint.
    ///
    /// LM Studio's native REST API always lives at the server root (`/api/v1/models`), regardless
    /// of the chat API's base path. The endpoint is therefore derived by keeping only the scheme,
    /// host, and port of `baseURL` and replacing the path — so `http://localhost:1234/v1`,
    /// `http://localhost:1234/v1/`, and a bare `http://localhost:1234` all yield
    /// `http://localhost:1234/api/v1/models`. This is a best-effort, unauthenticated probe: any
    /// failure (unparseable URL, network error, non-200, undecodable body, missing window) yields `nil`.
    ///
    /// - Parameters:
    ///   - baseURL: The provider base URL, e.g. `http://localhost:1234/v1`.
    ///   - model: The model identifier as reported by the local server.
    ///   - urlSession: The session used for the request. Defaults to ``URLSession/shared``.
    package static func contextWindow(
        baseURL: URL,
        model: String,
        urlSession: URLSession = .shared,
    ) async -> Int? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/api/v1/models"
        components.query = nil
        components.fragment = nil
        guard let endpoint = components.url else {
            return nil
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        guard
            let (data, response) = try? await urlSession.data(for: request),
            let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
            let list = try? JSONDecoder().decode(LMStudioV1List.self, from: data)
        else {
            return nil
        }
        return list.contextWindow(for: model)
    }
}

/// Decoded subset of LM Studio's `/api/v1/models` list payload.
private struct LMStudioV1List: Decodable {
    let models: [LMStudioV1Model]

    /// Served context window for `model`: the loaded instance's configured length (what the
    /// server is actually serving), falling back to the model's theoretical maximum.
    func contextWindow(for model: String) -> Int? {
        guard let entry = models.first(where: { $0.key == model }) else {
            return nil
        }
        return entry.loadedInstances.first?.config.contextLength ?? entry.maxContextLength
    }
}

private struct LMStudioV1Model: Decodable {
    let key: String
    let maxContextLength: Int?
    let loadedInstances: [LMStudioV1Instance]

    enum CodingKeys: String, CodingKey {
        case key
        case maxContextLength = "max_context_length"
        case loadedInstances = "loaded_instances"
    }
}

private struct LMStudioV1Instance: Decodable {
    let config: LMStudioV1InstanceConfig
}

private struct LMStudioV1InstanceConfig: Decodable {
    let contextLength: Int?

    enum CodingKeys: String, CodingKey {
        case contextLength = "context_length"
    }
}
#endif
