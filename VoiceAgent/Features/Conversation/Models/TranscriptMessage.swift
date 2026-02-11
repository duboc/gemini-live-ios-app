import Foundation

struct TranscriptMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    enum Role: String, Sendable, Equatable {
        case user
        case agent
        case system
    }

    init(role: Role, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = Date()
    }
}
