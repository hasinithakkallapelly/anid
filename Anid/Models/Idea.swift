import Foundation
import SwiftData

enum IdeaStatus: String, Codable {
    case inbox
    case processed
}

@Model
final class Idea {
    @Attribute(.unique) var id: UUID
    var rawText: String
    var sourceURLString: String?
    var createdAt: Date
    var statusRaw: String
    var summary: String?

    /// Filename (relative to the shared App Group's Videos folder) of a video
    /// attached at capture time, e.g. a reel saved from Instagram and
    /// picked from Photos. When set, Gemini analyzes the actual video
    /// content instead of only the typed text.
    var localVideoFilename: String?

    /// Caches the Gemini Files API upload for localVideoFilename so repeat
    /// requests (a re-run of the breakdown, or a chat follow-up) don't
    /// re-upload the same video. Files API uploads expire after 48 hours,
    /// after which geminiFileExpiresAt tells callers to upload again.
    var geminiFileURI: String?
    var geminiFileMimeType: String?
    var geminiFileExpiresAt: Date?

    var goal: Goal?

    /// What the reel assumes you already know or have, from the breakdown.
    var prerequisites: [String] = []

    /// How this idea moves the linked goal forward. Only set when the idea
    /// had a goal at breakdown time.
    var goalConnection: String?

    @Relationship(deleteRule: .cascade, inverse: \TodoItem.idea)
    var todoItems: [TodoItem] = []

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.idea)
    var chatMessages: [ChatMessage] = []

    var status: IdeaStatus {
        get { IdeaStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        rawText: String,
        sourceURLString: String? = nil,
        localVideoFilename: String? = nil,
        goal: Goal? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.sourceURLString = sourceURLString
        self.createdAt = Date()
        self.statusRaw = IdeaStatus.inbox.rawValue
        self.summary = nil
        self.localVideoFilename = localVideoFilename
        self.goal = goal
    }
}
