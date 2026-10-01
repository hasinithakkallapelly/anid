import Foundation
import SwiftData

enum ChatRole: String, Codable {
    case user
    case model
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var text: String
    var createdAt: Date
    var idea: Idea?

    var role: ChatRole {
        get { ChatRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), role: ChatRole, text: String, idea: Idea? = nil) {
        self.id = id
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = Date()
        self.idea = idea
    }
}
