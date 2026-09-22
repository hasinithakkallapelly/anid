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

    @Relationship(deleteRule: .cascade, inverse: \TodoItem.idea)
    var todoItems: [TodoItem] = []

    var status: IdeaStatus {
        get { IdeaStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), rawText: String, sourceURLString: String? = nil) {
        self.id = id
        self.rawText = rawText
        self.sourceURLString = sourceURLString
        self.createdAt = Date()
        self.statusRaw = IdeaStatus.inbox.rawValue
        self.summary = nil
    }
}
