import Foundation

// Gemini 2.5 Flash — BYOK
// API key from: https://aistudio.google.com/apikey
// Uses Google's OpenAI-compatible endpoint, so it reuses OpenAICompatibleResponse.

final class GeminiProvider: AIProvider {
    let name = "Gemini"
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    private let model = "gemini-2.5-flash"

    init(apiKey: String) { self.apiKey = apiKey }
    var isAvailable: Bool { !apiKey.isEmpty }

    func reply(messages: [ChatTurn], imageURL: URL?, plan: RoutingPlan) async throws -> String {
        guard isAvailable else { throw AIError.noAPIKey(provider: name) }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Gemini 2.5 Flash spends "thinking" tokens that count against max_tokens on
        // Google's OpenAI-compat endpoint. A tight per-action ceiling could be eaten
        // entirely by thinking, starving the visible answer (the 2.5-Flash cutoff —
        // see lessons). So add reasoning headroom + a floor on top of the requested
        // ceiling, with reasoning_effort: low to keep thinking minimal.
        let cap = max(plan.maxOutputTokens + 1024, 2048)
        let body: [String: Any] = [
            "model": model,
            "messages": openAICompatMessages(messages, imageURL: imageURL, attachImage: true),
            "max_tokens": cap,
            "temperature": 0.3,
            "reasoning_effort": "low"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AIError.apiError(data.apiErrorMessage() ?? "HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
        return decoded.choices.first?.message.content ?? "No response"
    }
}
