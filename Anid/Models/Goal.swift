import Foundation
import SwiftData

/// Something bigger the user is working toward — "learn guitar", "get
/// better at iOS dev" — that individual saved reels feed into. Linking an
/// Idea to a Goal makes its breakdown goal-aware: Gemini plans around what
/// actually moves the user toward this, not just what the reel literally
/// shows.
@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    var title: String
    /// Optional elaboration: what "achieved" looks like, current level,
    /// timeframe. Passed to Gemini so prerequisites and steps can be pitched
    /// at the right starting point.
    var details: String?
    var createdAt: Date

    /// Nullify, not cascade: deleting a goal shouldn't delete the reels
    /// saved under it — they're still useful on their own.
    @Relationship(deleteRule: .nullify, inverse: \Idea.goal)
    var ideas: [Idea] = []

    init(id: UUID = UUID(), title: String, details: String? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.createdAt = Date()
    }
}
