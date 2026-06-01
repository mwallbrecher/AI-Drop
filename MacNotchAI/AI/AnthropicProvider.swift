import Foundation

// Claude Haiku — cheapest option for BYOK users.
// API key from: https://console.anthropic.com

final class AnthropicProvider: AIProvider {
    let name = "Anthropic"
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-haiku-4-5-20251001"
    /// Anthropic won't cache a block below ~2048 tokens on Haiku. At ~4 chars/token
    /// that's ~8k chars; below it we skip the `cache_control` mark entirely.
    private static let cacheMinChars = 8000

    init(apiKey: String) { self.apiKey = apiKey }
    var isAvailable: Bool { !apiKey.isEmpty }

    func reply(messages turns: [ChatTurn], imageURL: URL?, plan: RoutingPlan) async throws -> String {
        guard isAvailable else { throw AIError.noAPIKey(provider: name) }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Anthropic takes the system prompt in a separate top-level field; only
        // user/assistant turns go in `messages`. Image is inlined into the FIRST
        // user turn using Anthropic's own content-block format.
        let systemPrompt = turns.filter { $0.role == "system" }
            .map(\.content).joined(separator: "\n\n")

        var imageUsed = false
        let messages: [[String: Any]] = turns.compactMap { turn in
            guard turn.role == "user" || turn.role == "assistant" else { return nil }
            if turn.role == "user", !imageUsed,
               let imageURL, FileInspector.isImageFile(imageURL),
               let imageData = try? Data(contentsOf: imageURL) {
                imageUsed = true
                let base64 = imageData.base64EncodedString()
                let mime = mimeType(for: imageURL)
                return [
                    "role": "user",
                    "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": mime, "data": base64]],
                        ["type": "text", "text": turn.flattenedContent]
                    ]
                ]
            }
            // Document on the first user turn → split into a cacheable block. The doc
            // is byte-identical on every follow-up, so the prefix [system + this turn]
            // hits the cache (~90% off the replayed document tokens). Only mark it when
            // it's plausibly above Haiku's ~2048-token cache minimum — below that the
            // mark is a no-op and a short prompt isn't worth caching anyway.
            if turn.role == "user", let doc = turn.cacheableDocument,
               doc.count >= Self.cacheMinChars {
                return [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": turn.content],
                        ["type": "text", "text": "--- Document(s) ---\n" + doc,
                         "cache_control": ["type": "ephemeral"]]
                    ]
                ]
            }
            return ["role": turn.role, "content": turn.flattenedContent]
        }

        let body: [String: Any] = [
            "model": model,
            "system": systemPrompt,
            "messages": messages,
            "max_tokens": plan.maxOutputTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AIError.apiError(data.apiErrorMessage() ?? "HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.first?.text ?? "No response"
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        default:            return "image/jpeg"
        }
    }
}

struct AnthropicResponse: Decodable {
    let content: [ContentBlock]
    struct ContentBlock: Decodable {
        let text: String
    }
}
