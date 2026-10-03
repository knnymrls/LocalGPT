import Foundation

struct MemoryItem: Identifiable, Hashable, Sendable {
    enum State: Sendable { case proposed, saved, forgotten }

    let id: UUID
    var text: String
    /// e.g. "From this chat · Today"
    var origin: String
    /// e.g. "This workspace"
    var scope: String
    var state: State

    init(id: UUID = UUID(), text: String, origin: String, scope: String = "This workspace", state: State) {
        self.id = id
        self.text = text
        self.origin = origin
        self.scope = scope
        self.state = state
    }
}
