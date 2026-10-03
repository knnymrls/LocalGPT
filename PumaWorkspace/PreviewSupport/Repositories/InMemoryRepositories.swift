#if DEBUG
import Foundation

actor InMemoryConversationRepository: ConversationRepository {
    private var items: [UUID: Conversation]
    init(_ seed: [Conversation]) { items = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) }) }
    func all() -> [Conversation] { items.values.sorted { $0.updatedAt > $1.updatedAt } }
    func save(_ conversation: Conversation) { items[conversation.id] = conversation }
    func delete(id: UUID) { items[id] = nil }
}

actor InMemoryAttachmentRepository: AttachmentRepository {
    private var items: [Attachment]
    init(_ seed: [Attachment]) { items = seed }
    func all() -> [Attachment] { items }
    func save(_ attachment: Attachment) {
        if let i = items.firstIndex(where: { $0.id == attachment.id }) { items[i] = attachment } else { items.append(attachment) }
    }
    func delete(id: UUID) { items.removeAll { $0.id == id } }
}

actor InMemoryMemoryRepository: MemoryRepository {
    private var items: [MemoryItem]
    init(_ seed: [MemoryItem]) { items = seed }
    func all() -> [MemoryItem] { items }
    func insertIfNew(_ item: MemoryItem) -> Bool {
        guard !items.contains(where: { $0.fingerprint == item.fingerprint }) else { return false }
        items.append(item)
        return true
    }
    func save(_ item: MemoryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
    }
    func delete(id: UUID) { items.removeAll { $0.id == id } }
}

struct FixtureModelCatalog: ModelCatalog {
    var defaultModelID: String { Fixtures.models.first?.id ?? "preview.model" }
    func models() async -> [LocalModel] { Fixtures.models }
}
#endif
