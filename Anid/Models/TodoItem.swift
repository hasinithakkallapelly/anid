import Foundation
import SwiftData

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var text: String
    var notes: String?
    /// When set, this step gets a one-shot local notification in Remind Me
    /// at this date/time once sent — see RemindMeBridge. Mutually exclusive
    /// with placeName in practice (the UI enforces at most one trigger),
    /// though nothing stops both from being set.
    var dueDate: Date?
    /// When set, this step should fire when the user enters a specific
    /// place instead of at a specific time — e.g. a laptop-only task
    /// suggests "Room". Must match one of the user's actual saved Remind Me
    /// place names (case-insensitively) to actually trigger anything there;
    /// see RemindMeBridge and Docs/RemindMeIntegration.md.
    var placeName: String?
    var isSentToRemindMe: Bool
    var createdAt: Date
    var idea: Idea?

    init(
        id: UUID = UUID(),
        text: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        placeName: String? = nil,
        idea: Idea? = nil
    ) {
        self.id = id
        self.text = text
        self.notes = notes
        self.dueDate = dueDate
        self.placeName = placeName
        self.isSentToRemindMe = false
        self.createdAt = Date()
        self.idea = idea
    }
}
