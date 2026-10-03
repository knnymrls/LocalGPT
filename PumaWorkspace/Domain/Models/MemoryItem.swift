import Foundation

struct MemoryItem: Identifiable, Hashable, Codable, Sendable {
    enum State: Codable, Sendable { case proposed, saved, forgotten }

    let id: UUID
    var text: String
    /// e.g. "From this chat · Today"
    var origin: String
    /// e.g. "This workspace"
    var scope: String
    var state: State
    var conversationID: UUID?
    var messageID: UUID?
    var sourceQuote: String = ""
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var fingerprint: String = ""

    init(id: UUID = UUID(), text: String, origin: String, scope: String = "This workspace", state: State) {
        self.id = id
        self.text = text
        self.origin = origin
        self.scope = scope
        self.state = state
    }
}
