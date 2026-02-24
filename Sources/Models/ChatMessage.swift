import Foundation

// MARK: - Chat Message

/// A message in the AI chat conversation.
struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: Sendable {
        case user
        case assistant
    }

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
