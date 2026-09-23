import Foundation

/// Models available for breaking down an idea, via Google's Gemini API free
/// tier (no card, no expiry, ~1,500 requests/day as of writing). Both are
/// free — Flash gives more thorough breakdowns, Flash-Lite responds faster
/// and uses less of the daily quota.
enum GeminiModel: String, CaseIterable, Identifiable {
    case flash = "gemini-2.5-flash"
    case flashLite = "gemini-2.5-flash-lite"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flash: return "Gemini 2.5 Flash (more thorough)"
        case .flashLite: return "Gemini 2.5 Flash-Lite (fastest)"
        }
    }
}

struct IdeaBreakdown {
    let summary: String
    let todoItems: [TodoDraft]

    struct TodoDraft {
        let text: String
        let notes: String?
        let dueDate: Date?
        let placeName: String?
    }
}

enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case invalidHTTPResponse
    case httpError(status: Int, body: String)
    case blocked(reason: String)
    case emptyContent
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Gemini API key set. Add one in Settings."
        case .invalidHTTPResponse:
            return "Unexpected response from the Gemini API."
        case .httpError(let status, let body):
            return "Gemini API error (\(status)): \(body)"
        case .blocked(let reason):
            return "Gemini declined to process this idea (\(reason))."
        case .emptyContent:
            return "Gemini returned an empty response."
        case .decodingFailed(let detail):
            return "Couldn't parse Gemini's response: \(detail)"
        }
    }
}

/// Talks to the Gemini API directly over HTTPS — there's no official Google
/// SDK for Swift, so this is raw URLSession + JSON rather than a client
/// library.
enum GeminiService {
    static func breakDown(
        idea: Idea,
        apiKey: String,
        model: GeminiModel,
        knownPlaces: [String]
    ) async throws -> IdeaBreakdown {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw GeminiServiceError.missingAPIKey
        }
        guard let endpoint = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent"
        ) else {
            throw GeminiServiceError.invalidHTTPResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(idea: idea, knownPlaces: knownPlaces)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GeminiServiceError.httpError(status: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

        if let blockReason = decoded.promptFeedback?.blockReason {
            throw GeminiServiceError.blocked(reason: blockReason)
        }
        guard let candidate = decoded.candidates?.first else {
            throw GeminiServiceError.emptyContent
        }
        if let finishReason = candidate.finishReason, finishReason != "STOP" {
            throw GeminiServiceError.blocked(reason: finishReason)
        }
        guard let text = candidate.content?.parts.first(where: { $0.text != nil })?.text, !text.isEmpty else {
            throw GeminiServiceError.emptyContent
        }

        do {
            let parsed = try JSONDecoder().decode(BreakdownJSON.self, from: Data(text.utf8))
            let isoFormatter = ISO8601DateFormatter()
            let todoItems = parsed.todoItems.map { item -> IdeaBreakdown.TodoDraft in
                let due = item.dueDate.flatMap { isoFormatter.date(from: $0) }
                return IdeaBreakdown.TodoDraft(text: item.text, notes: item.notes, dueDate: due, placeName: item.placeName)
            }
            return IdeaBreakdown(summary: parsed.summary, todoItems: todoItems)
        } catch {
            throw GeminiServiceError.decodingFailed(error.localizedDescription)
        }
    }

    private static func requestBody(idea: Idea, knownPlaces: [String]) -> [String: Any] {
        let today = ISO8601DateFormatter().string(from: Date())
        var userContent = "Today's date: \(today)\n\nIdea / note:\n\(idea.rawText)"
        if let link = idea.sourceURLString, !link.isEmpty {
            userContent += "\n\nSource link: \(link)"
        }
        if knownPlaces.isEmpty {
            userContent += "\n\nThe user hasn't listed any saved Remind Me places yet, so never set placeName — leave every step's placeName null."
        } else {
            userContent += "\n\nThe user's saved Remind Me places: \(knownPlaces.joined(separator: ", ")). Only use one of these exact names for placeName — never invent a new one."
        }

        // Gemini's response_schema dialect uses uppercase type names and a
        // `nullable` flag rather than JSON Schema's `anyOf`-with-null.
        let nullableString: [String: Any] = ["type": "STRING", "nullable": true]

        return [
            "contents": [
                ["role": "user", "parts": [["text": userContent]]]
            ],
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "generationConfig": [
                "maxOutputTokens": 4096,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "summary": ["type": "STRING"],
                        "todoItems": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "text": ["type": "STRING"],
                                    "notes": nullableString,
                                    "dueDate": nullableString,
                                    "placeName": nullableString
                                ],
                                "required": ["text", "notes", "dueDate", "placeName"]
                            ]
                        ]
                    ],
                    "required": ["summary", "todoItems"]
                ]
            ]
        ]
    }

    private static let systemPrompt = """
    You turn a quickly captured idea — often a note about a social media reel, \
    a skill, tool, or technique the user wants to learn or do — into a short, \
    concrete action plan.

    Rules:
    - Read the raw text (and source link, if present) as the user's own note \
    about what they want to learn, try, or remember to do. If it names \
    something you recognize (a specific tool, skill, technique, or product), \
    use what you actually know about it to give real, specific guidance. If \
    it's vague, make reasonable assumptions and say so in the summary.
    - "summary" is 1-3 sentences: what this idea is and why it's worth doing.
    - "todoItems" is 3-7 concrete, ordered action steps — not vague advice. \
    E.g. "Read the official docs at X" or "Install X and run the quickstart" \
    rather than "learn more about X".
    - Each step gets at most one reminder trigger: either a dueDate (time) \
    or a placeName (place) — never both, and most steps need neither.
    - Set placeName only when the step is naturally tied to being physically \
    somewhere specific — e.g. a step that needs a laptop/desk setup fits a \
    "Room" or "Office" place; a step that needs gym equipment fits "Gym". \
    Only use one of the user's listed places (given below), matched exactly; \
    if none of their places fit the step, leave placeName null rather than \
    inventing one.
    - Set a dueDate instead when the note implies real urgency or a specific \
    timeframe (e.g. "this weekend", "before Friday") and the step isn't \
    place-bound. Most ideas don't need an artificial deadline — leave it \
    null unless the timeframe is actually implied.
    - dueDate, when set, must be a full ISO 8601 date-time string, computed \
    relative to today's date given above.
    - notes may add one short clarifying detail per step (a link, a command, \
    a tip); leave it null if there's nothing to add.
    - Respond with only the JSON object described by the response schema — \
    no surrounding prose.
    """

    private struct GenerateContentResponse: Decodable {
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?

        struct Candidate: Decodable {
            let content: Content?
            let finishReason: String?
        }
        struct Content: Decodable {
            let parts: [Part]
        }
        struct Part: Decodable {
            let text: String?
        }
        struct PromptFeedback: Decodable {
            let blockReason: String?
        }
    }

    private struct BreakdownJSON: Decodable {
        let summary: String
        let todoItems: [TodoDraftJSON]
        struct TodoDraftJSON: Decodable {
            let text: String
            let notes: String?
            let dueDate: String?
            let placeName: String?
        }
    }
}
