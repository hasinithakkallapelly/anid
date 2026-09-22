import Foundation

/// Models available for breaking down an idea. Opus 5 gives the most
/// thorough breakdowns; Sonnet 5 / Haiku 4.5 cost less per idea — the user
/// picks in Settings, since that's a cost/quality tradeoff only they should
/// make.
enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus5 = "claude-opus-5"
    case sonnet5 = "claude-sonnet-5"
    case haiku45 = "claude-haiku-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus5: return "Opus 5 (best quality, highest cost)"
        case .sonnet5: return "Sonnet 5 (balanced)"
        case .haiku45: return "Haiku 4.5 (fastest, cheapest)"
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
    }
}

enum ClaudeServiceError: LocalizedError {
    case missingAPIKey
    case invalidHTTPResponse
    case httpError(status: Int, body: String)
    case refusal
    case emptyContent
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Claude API key set. Add one in Settings."
        case .invalidHTTPResponse:
            return "Unexpected response from the Claude API."
        case .httpError(let status, let body):
            return "Claude API error (\(status)): \(body)"
        case .refusal:
            return "Claude declined to process this idea."
        case .emptyContent:
            return "Claude returned an empty response."
        case .decodingFailed(let detail):
            return "Couldn't parse Claude's response: \(detail)"
        }
    }
}

/// Talks to the Claude Messages API directly over HTTPS — there's no
/// official Anthropic SDK for Swift, so this is raw URLSession + JSON
/// rather than a client library.
enum ClaudeService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func breakDown(idea: Idea, apiKey: String, model: ClaudeModel) async throws -> IdeaBreakdown {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ClaudeServiceError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(idea: idea, model: model))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeServiceError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeServiceError.httpError(status: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        if decoded.stop_reason == "refusal" {
            throw ClaudeServiceError.refusal
        }
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw ClaudeServiceError.emptyContent
        }

        do {
            let parsed = try JSONDecoder().decode(BreakdownJSON.self, from: Data(text.utf8))
            let isoFormatter = ISO8601DateFormatter()
            let todoItems = parsed.todoItems.map { item -> IdeaBreakdown.TodoDraft in
                let due = item.dueDate.flatMap { isoFormatter.date(from: $0) }
                return IdeaBreakdown.TodoDraft(text: item.text, notes: item.notes, dueDate: due)
            }
            return IdeaBreakdown(summary: parsed.summary, todoItems: todoItems)
        } catch {
            throw ClaudeServiceError.decodingFailed(error.localizedDescription)
        }
    }

    private static func requestBody(idea: Idea, model: ClaudeModel) -> [String: Any] {
        let today = ISO8601DateFormatter().string(from: Date())
        var userContent = "Today's date: \(today)\n\nIdea / note:\n\(idea.rawText)"
        if let link = idea.sourceURLString, !link.isEmpty {
            userContent += "\n\nSource link: \(link)"
        }

        let nullableString: [String: Any] = [
            "anyOf": [
                ["type": "string"],
                ["type": "null"]
            ]
        ]
        let nullableDate: [String: Any] = [
            "anyOf": [
                ["type": "string", "format": "date-time"],
                ["type": "null"]
            ]
        ]

        return [
            "model": model.rawValue,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userContent]
            ],
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": [
                        "type": "object",
                        "properties": [
                            "summary": ["type": "string"],
                            "todoItems": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "text": ["type": "string"],
                                        "notes": nullableString,
                                        "dueDate": nullableDate
                                    ],
                                    "required": ["text", "notes", "dueDate"],
                                    "additionalProperties": false
                                ]
                            ]
                        ],
                        "required": ["summary", "todoItems"],
                        "additionalProperties": false
                    ]
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
    - Only set a dueDate when the note implies real urgency or a specific \
    timeframe (e.g. "this weekend", "before Friday"). Otherwise leave it \
    null — most ideas don't need an artificial deadline.
    - dueDate, when set, must be a full ISO 8601 date-time string, computed \
    relative to today's date given above.
    - notes may add one short clarifying detail per step (a link, a command, \
    a tip); leave it null if there's nothing to add.
    """

    private struct MessagesResponse: Decodable {
        let content: [ContentBlock]
        let stop_reason: String?
        struct ContentBlock: Decodable { let type: String; let text: String? }
    }

    private struct BreakdownJSON: Decodable {
        let summary: String
        let todoItems: [TodoDraftJSON]
        struct TodoDraftJSON: Decodable {
            let text: String
            let notes: String?
            let dueDate: String?
        }
    }
}
