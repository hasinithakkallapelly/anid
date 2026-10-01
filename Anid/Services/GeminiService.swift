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
    let goalConnection: String?
    let prerequisites: [String]
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
                return IdeaBreakdown.TodoDraft(text: item.text, notes: item.details, dueDate: due, placeName: item.placeName)
            }
            let goalConnection = parsed.goalConnection?.trimmingCharacters(in: .whitespacesAndNewlines)
            return IdeaBreakdown(
                summary: parsed.summary,
                goalConnection: (goalConnection?.isEmpty ?? true) ? nil : goalConnection,
                prerequisites: (parsed.prerequisites ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                todoItems: todoItems
            )
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

    /// The user's goal, if this idea is linked to one — shared by the
    /// breakdown and chat so both pitch advice at the same target.
    private static func goalContext(for idea: Idea) -> String? {
        guard let goal = idea.goal else { return nil }
        var text = "The user's goal this is meant to serve: \(goal.title)"
        if let details = goal.details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
            text += "\nMore about that goal (their words): \(details)"
        }
        return text
    }

    private static func breakdownRequestBody(idea: Idea, knownPlaces: [String], videoFile: GeminiUploadedFile?) -> [String: Any] {
        let today = ISO8601DateFormatter().string(from: Date())
        var userContent = "Today's date: \(today)"
        if idea.rawText.isEmpty {
            userContent += "\n\nThe user didn't type a note — work from the video alone."
        } else {
            userContent += "\n\nUser's note:\n\(idea.rawText)"
        }
        if let link = idea.sourceURLString, !link.isEmpty {
            userContent += "\n\nSource link (for reference only — you can't open it): \(link)"
        }
        if videoFile != nil {
            userContent += "\n\nThe reel's video is attached — watch and listen to it. Base everything on what's actually shown and said."
        }
        if let goal = goalContext(for: idea) {
            userContent += "\n\n\(goal)"
        } else {
            userContent += "\n\nNo goal is linked, so set goalConnection to null and infer the most likely reason someone saves a reel like this."
        }
        if knownPlaces.isEmpty {
            userContent += "\n\nThe user hasn't listed any saved Remind Me places, so leave every step's placeName null."
        } else {
            userContent += "\n\nThe user's saved Remind Me places: \(knownPlaces.joined(separator: ", ")). Only use one of these exact names for placeName — never invent one."
        }

        var parts: [[String: Any]] = []
        if let filePart = filePart(for: videoFile) {
            parts.append(filePart)
        }
        parts.append(["text": userContent])

        // Gemini's response_schema dialect uses uppercase type names and a
        // `nullable` flag rather than JSON Schema's `anyOf`-with-null.
        // propertyOrdering makes the model write the goal link and
        // prerequisites before the steps, so the steps build on them
        // instead of the reasoning being bolted on after.
        let nullableString: [String: Any] = ["type": "STRING", "nullable": true]

        return [
            "contents": [
                ["role": "user", "parts": parts]
            ],
            "systemInstruction": [
                "parts": [["text": breakdownSystemPrompt]]
            ],
            "generationConfig": [
                // Detailed steps are long, and on Gemini's thinking models
                // the reasoning counts against this limit too — too low and
                // the response gets cut off mid-JSON (finishReason MAX_TOKENS).
                "maxOutputTokens": 16384,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "summary": ["type": "STRING"],
                        "goalConnection": nullableString,
                        "prerequisites": [
                            "type": "ARRAY",
                            "items": ["type": "STRING"]
                        ],
                        "todoItems": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "text": ["type": "STRING"],
                                    "details": ["type": "STRING"],
                                    "dueDate": nullableString,
                                    "placeName": nullableString
                                ],
                                "required": ["text", "details", "dueDate", "placeName"],
                                "propertyOrdering": ["text", "details", "dueDate", "placeName"]
                            ]
                        ]
                    ],
                    "required": ["summary", "goalConnection", "prerequisites", "todoItems"],
                    "propertyOrdering": ["summary", "goalConnection", "prerequisites", "todoItems"]
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
        var contextText = idea.rawText.isEmpty ? "The user saved a reel without a note." : "User's note:\n\(idea.rawText)"
        if let link = idea.sourceURLString, !link.isEmpty {
            contextText += "\n\nSource link (for reference only): \(link)"
        }
        if videoFile != nil {
            contextText += "\n\nThe reel's video is attached — you can see and hear it directly."
        }
        if let goal = goalContext(for: idea) {
            contextText += "\n\n\(goal)"
        }
        if let summary = idea.summary {
            contextText += "\n\nSummary you already gave: \(summary)"
        }
        if let connection = idea.goalConnection {
            contextText += "\n\nHow you said it connects to their goal: \(connection)"
        }
        if !idea.prerequisites.isEmpty {
            contextText += "\n\nPrerequisites you listed:\n" + idea.prerequisites.map { "- \($0)" }.joined(separator: "\n")
        }
        if !idea.todoItems.isEmpty {
            let steps = idea.todoItems
                .sorted { $0.createdAt < $1.createdAt }
                .enumerated()
                .map { index, item in
                    "\(index + 1). \(item.text)" + (item.notes.map { "\n   \($0)" } ?? "")
                }
                .joined(separator: "\n")
            contextText += "\n\nSteps you already gave:\n\(steps)"
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
            "parts": [["text": "Got it — I have the reel, your goal, and the plan. What do you want to dig into?"]]
        ])

        for message in history {
            contents.append(["role": message.role.rawValue, "parts": [["text": message.text]]])
        }
        contents.append(["role": "user", "parts": [["text": newMessage]]])

        return [
            "contents": contents,
            "systemInstruction": ["parts": [["text": chatSystemPrompt]]],
            "generationConfig": ["maxOutputTokens": 8192]
        ]
    }

    private static let breakdownSystemPrompt = """
    You're a learning coach. The user saves reels about things they want to \
    learn or do, then never gets back to them. Your job is to turn one saved \
    reel into a plan they will actually follow — one that gets them closer \
    to what they're really after, not just a recap of the reel.

    How to think about it:
    - First work out what the reel actually teaches or shows. If a video is \
    attached, watch and listen to it and use its specifics (exact tools, \
    commands, settings, ingredients, techniques, numbers). If the note names \
    something you recognize, use what you really know about it. If you're \
    unsure of a detail, say so rather than inventing one.
    - Then work out the bigger thing the user is trying to get to. If a goal \
    is given, that's it. If not, infer the most likely one.
    - Reels skip the foundations and assume the viewer already has them. \
    Identify what this reel assumes — knowledge, skills, tools, accounts, \
    setup — and list it in "prerequisites". Pitch these for someone who may \
    be earlier on than the reel assumes; over-listing a genuinely \
    foundational item is better than skipping it.
    - The steps are a learning path, in order: close any prerequisite gaps \
    first, then do the core of what the reel shows, then practice it on \
    something real, then check the result, then one step that extends it \
    toward the goal. Steps should be small enough to start today.

    Fields:
    - "summary": 2-3 sentences — what the reel teaches and why it's useful.
    - "goalConnection": when a goal is given, 1-2 sentences on how this reel \
    moves them toward it. If it's only loosely related, say that plainly \
    instead of overselling it. null when no goal is given.
    - "prerequisites": 2-6 short items, e.g. "Comfortable with basic Python \
    syntax (variables, loops)" or "A free GitHub account". Each should be \
    specific enough that the user can tell whether they already have it.
    - "todoItems": 4-10 steps in learning-path order.
      - "text": a short, specific action that starts with a verb, e.g. \
    "Install Obsidian and create a vault for your notes" — not "Learn about \
    Obsidian".
      - "details": the real content of the step, 3-6 sentences. Say exactly \
    what to do (concrete commands, settings, menu paths, examples, amounts), \
    why it matters for the goal, how they'll know it's done, and one common \
    mistake or tip. Write it so someone could follow it without rewatching \
    the reel. Never leave this vague or empty.
    - Each step gets at most one reminder trigger: "dueDate" (time) or \
    "placeName" (place) — never both, and most steps need neither.
    - Set placeName only when the step naturally happens somewhere \
    specific — a step needing a laptop or desk fits "Room" or "Office"; one \
    needing gym equipment fits "Gym". Only use one of the user's listed \
    places, matched exactly; if none fit, leave it null.
    - Set dueDate only when the note implies a real deadline or timeframe \
    ("this weekend", "before Friday"). Otherwise null. When set, it must be \
    a full ISO 8601 date-time computed from today's date.

    Respond with only the JSON object described by the response schema.
    """

    private static let chatSystemPrompt = """
    You're a learning coach helping the user follow through on a reel they \
    saved, after you've already given them prerequisites and a step-by-step \
    plan toward their goal. Now help them actually do it: explain a step in \
    more depth, teach a prerequisite they're missing, troubleshoot what went \
    wrong, adjust the plan to their level, or tell them what to do next.

    - If a video is attached, refer to its specifics (what's shown, said, on \
    screen) rather than speaking in generalities.
    - When they're missing a prerequisite, teach it — start simple, use a \
    concrete example, then connect it back to the step it unblocks.
    - Prefer one clear next action over a list of options.
    - Keep replies focused and readable on a phone: short paragraphs, \
    numbered steps when order matters, no walls of text.
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
        let goalConnection: String?
        let prerequisites: [String]?
        let todoItems: [TodoDraftJSON]
        struct TodoDraftJSON: Decodable {
            let text: String
            let details: String?
            let dueDate: String?
            let placeName: String?
        }
    }
}
