import Foundation
import SwiftData

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var text: String
    var notes: String?
    /// When set, this step gets a one-shot local notification in Remind Me
    /// at this date/time once sent — see RemindMeBridge. Left nil for most
    /// steps; only set when the idea implied real urgency or a timeframe.
    var dueDate: Date?
    var isSentToRemindMe: Bool
    var createdAt: Date
    var idea: Idea?

    init(
        id: UUID = UUID(),
        text: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        idea: Idea? = nil
    ) {
        self.id = id
        self.text = text
        self.notes = notes
        self.dueDate = dueDate
        self.isSentToRemindMe = false
        self.createdAt = Date()
        self.idea = idea
    }
}
