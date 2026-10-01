import Foundation

/// Models available for breaking down an idea, via Google's Gemini API free
/// tier (no card, no expiry). Google's free-tier request caps and model
/// lineup have both shifted before (this app has already been bitten once
/// by a retired model ID) — as of writing, Flash-Lite gets ~500 free
/// requests/day versus Flash's ~20/day, so Flash-Lite is the default
/// despite Flash being the more capable model. If either ID ever 404s
/// again with a "no longer available" message like Gemini did before,
/// the error names the replacement — swap it in here.
enum GeminiModel: String, CaseIterable, Identifiable {
    case flashLite = "gemini-3.5-flash-lite"
    case flash = "gemini-3.8-flash"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flashLite: return "Gemini 3.5 Flash-Lite (default — ~500 free req/day)"
        case .flash: return "Gemini 3.8 Flash (more thorough — ~20 free req/day)"
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
    /// Uploads the idea's attached video (if any) to the Gemini Files API,
    /// reusing a still-valid prior upload cached on the Idea when possible
    /// — uploads expire after 48 hours, so this re-uploads once that's
    /// close. Returns nil when the idea has no video.
    static func ensureUploadedVideo(for idea: Idea, apiKey: String) async throws -> GeminiUploadedFile? {
        guard let filename = idea.localVideoFilename else { return nil }

        if let uri = idea.geminiFileURI,
           let mimeType = idea.geminiFileMimeType,
           let expiresAt = idea.geminiFileExpiresAt,
           expiresAt > Date().addingTimeInterval(120) {
            return GeminiUploadedFile(name: "", uri: uri, mimeType: mimeType, expiresAt: expiresAt)
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw GeminiServiceError.missingAPIKey }

        let fileURL = VideoStorage.url(for: filename)
        let mimeType = VideoStorage.mimeType(for: filename)
        let uploaded = try await GeminiFilesService.upload(fileURL: fileURL, mimeType: mimeType, apiKey: trimmedKey)

        idea.geminiFileURI = uploaded.uri
        idea.geminiFileMimeType = uploaded.mimeType
        idea.geminiFileExpiresAt = uploaded.expiresAt

        return uploaded
    }

    static func breakDown(
        idea: Idea,
        apiKey: String,
        model: GeminiModel,
        knownPlaces: [String],
        videoFile: GeminiUploadedFile?
    ) async throws -> IdeaBreakdown {
        let text = try await performGenerateContent(
            body: breakdownRequestBody(idea: idea, knownPlaces: knownPlaces, videoFile: videoFile),
            apiKey: apiKey,
            model: model
        )

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

    /// Sends one chat turn about an already-captured (and possibly already
    /// broken-down) idea, with the idea's text/summary/steps — and its
    /// video, if attached — as context on every call, since the API is
    /// stateless and doesn't remember anything between requests on its own.
    static func sendChatMessage(
        idea: Idea,
        apiKey: String,
        model: GeminiModel,
        videoFile: GeminiUploadedFile?,
        history: [ChatMessage],
        newMessage: String
    ) async throws -> String {
        try await performGenerateContent(
            body: chatRequestBody(idea: idea, videoFile: videoFile, history: history, newMessage: newMessage),
            apiKey: apiKey,
            model: model
        )
    }

    private static func performGenerateContent(
        body: [String: Any],
        apiKey: String,
        model: GeminiModel
    ) async throws -> String {
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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw GeminiServiceError.httpError(status: httpResponse.statusCode, body: responseBody)
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
        return text
    }

    private static func filePart(for videoFile: GeminiUploadedFile?) -> [String: Any]? {
        guard let videoFile else { return nil }
        return ["fileData": ["fileUri": videoFile.uri, "mimeType": videoFile.mimeType]]
    }

    private static func breakdownRequestBody(idea: Idea, knownPlaces: [String], videoFile: GeminiUploadedFile?) -> [String: Any] {
        let today = ISO8601DateFormatter().string(from: Date())
        var userContent = "Today's date: \(today)\n\nIdea / note:\n\(idea.rawText)"
        if let link = idea.sourceURLString, !link.isEmpty {
            userContent += "\n\nSource link: \(link)"
        }
        if videoFile != nil {
            userContent += "\n\nA video is attached — base the breakdown on what's actually shown and said in it, not just the text above."
        }
        if knownPlaces.isEmpty {
            userContent += "\n\nThe user hasn't listed any saved Remind Me places yet, so never set placeName — leave every step's placeName null."
        } else {
            userContent += "\n\nThe user's saved Remind Me places: \(knownPlaces.joined(separator: ", ")). Only use one of these exact names for placeName — never invent a new one."
        }

        var parts: [[String: Any]] = []
        if let filePart = filePart(for: videoFile) {
            parts.append(filePart)
        }
        parts.append(["text": userContent])

        // Gemini's response_schema dialect uses uppercase type names and a
        // `nullable` flag rather than JSON Schema's `anyOf`-with-null.
        let nullableString: [String: Any] = ["type": "STRING", "nullable": true]

        return [
            "contents": [
                ["role": "user", "parts": parts]
            ],
            "systemInstruction": [
                "parts": [["text": breakdownSystemPrompt]]
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

    private static func chatRequestBody(
        idea: Idea,
        videoFile: GeminiUploadedFile?,
        history: [ChatMessage],
        newMessage: String
    ) -> [String: Any] {
        var contextText = "Idea / note:\n\(idea.rawText)"
        if let link = idea.sourceURLString, !link.isEmpty {
            contextText += "\n\nSource link: \(link)"
        }
        if videoFile != nil {
            contextText += "\n\nA video is attached to this idea — you can see and hear it directly."
        }
        if let summary = idea.summary {
            contextText += "\n\nSummary already given: \(summary)"
        }
        if !idea.todoItems.isEmpty {
            let steps = idea.todoItems
                .sorted { $0.createdAt < $1.createdAt }
                .enumerated()
                .map { index, item in "\(index + 1). \(item.text)" + (item.notes.map { " (\($0))" } ?? "") }
                .joined(separator: "\n")
            contextText += "\n\nSteps already generated:\n\(steps)"
        }

        var firstTurnParts: [[String: Any]] = []
        if let filePart = filePart(for: videoFile) {
            firstTurnParts.append(filePart)
        }
        firstTurnParts.append(["text": contextText])

        var contents: [[String: Any]] = [["role": "user", "parts": firstTurnParts]]
        // An acknowledgment turn makes the rest of the exchange read as a
        // normal back-and-forth instead of one giant opening message.
        contents.append([
            "role": "model",
            "parts": [["text": "Got it — I have the idea, its summary, and the steps. What would you like to go over?"]]
        ])

        for message in history {
            contents.append(["role": message.role.rawValue, "parts": [["text": message.text]]])
        }
        contents.append(["role": "user", "parts": [["text": newMessage]]])

        return [
            "contents": contents,
            "systemInstruction": ["parts": [["text": chatSystemPrompt]]],
            "generationConfig": ["maxOutputTokens": 2048]
        ]
    }

    private static let breakdownSystemPrompt = """
    You turn a quickly captured idea — often a note about a social media reel, \
    a skill, tool, or technique the user wants to learn or do — into a short, \
    concrete action plan.

    Rules:
    - Read the raw text (and source link, if present) as the user's own note \
    about what they want to learn, try, or remember to do. If it names \
    something you recognize (a specific tool, skill, technique, or product), \
    use what you actually know about it to give real, specific guidance. If \
    it's vague, make reasonable assumptions and say so in the summary.
    - If a video is attached, actually watch and listen to it — base the \
    breakdown on what's really shown, said, and demonstrated, not just the \
    typed text.
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

    private static let chatSystemPrompt = """
    You're helping the user follow through on an idea they captured in a \
    note-taking app, after already giving them a summary and a list of \
    concrete action steps. Keep helping conversationally now: answer \
    follow-up questions, go deeper on a step, troubleshoot problems they \
    hit, or suggest refinements. If a video was attached to the idea, you \
    can see and hear it directly — refer to specifics from it (what's \
    shown, what's said, on-screen text) rather than speaking in \
    generalities. Be concise and concrete; this is a chat, not another \
    formal breakdown.
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
