import Foundation

/// Real LLM client. Single HTTP path (`POST /chat/completions`) so the same
/// code works for OpenAI, Anthropic, and Google's OpenAI-compatible endpoint.
/// Reads provider/model/key from `LLMSettingsStore.snapshot` on every call so
/// edits in `SettingsView` take effect immediately.
final class LLMService: LLMServiceProtocol {
    private let settings: @Sendable () async -> LLMSettings
    private let urlSession: URLSession

    init(
        settings: @escaping @Sendable () async -> LLMSettings,
        urlSession: URLSession = .shared
    ) {
        self.settings = settings
        self.urlSession = urlSession
    }

    func generateTemplate(prompt: String) async throws -> ParsedTemplate {
        let snapshot = await settings()
        guard let apiKey = snapshot.apiKey, !apiKey.isEmpty else {
            throw LLMServiceError.missingAPIKey
        }

        let body = ChatRequest(
            model: snapshot.model,
            messages: [
                .init(role: "system", content: Prompts.systemPrompt),
                .init(role: "user",   content: Prompts.userPrompt(prompt))
            ],
            response_format: .init(type: "json_object")
        )

        var request = URLRequest(url: snapshot.provider.baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMServiceError.transport(message: "No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            #if DEBUG
            print("[LLMService] HTTP \(http.statusCode) error from \(snapshot.provider.baseURL.absoluteString):\n\(raw)")
            #endif
            throw LLMServiceError.httpStatus(code: http.statusCode, body: raw)
        }

        let chat: ChatResponse
        do {
            chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw LLMServiceError.envelopeDecodeFailed(raw: raw, underlying: error)
        }

        guard let content = chat.choices.first?.message.content, !content.isEmpty else {
            throw LLMServiceError.emptyContent
        }

        // Hand off to the same parser the mock uses — including the §3.5
        // isTimed invariant check.
        return try JSONParser.parseTemplate(from: content)
    }

    // MARK: - Wire types

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let response_format: ResponseFormat

        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct ResponseFormat: Encodable {
            let type: String
        }
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String
        }
    }
}

// MARK: - Errors

enum LLMServiceError: Error, LocalizedError {
    case missingAPIKey
    case transport(message: String)
    case httpStatus(code: Int, body: String)
    case envelopeDecodeFailed(raw: String, underlying: Error)
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured. Open Settings to add one."
        case .transport(let message):
            return "Network error: \(message)"
        case .httpStatus(let code, let body):
            let snippet = body.isEmpty ? "" : "\n\n\(body.prefix(600))"
            return "Model API error (HTTP \(code))." + snippet
        case .envelopeDecodeFailed:
            return "The model API returned an unexpected response shape."
        case .emptyContent:
            return "The model returned an empty message."
        }
    }
}
