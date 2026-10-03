import Foundation

protocol ConversationRepository: Sendable {
    func all() async throws -> [Conversation]
    func save(_ conversation: Conversation) async throws
    func delete(id: UUID) async throws
}

protocol AttachmentRepository: Sendable {
    func all() async throws -> [Attachment]
    func save(_ attachment: Attachment) async throws
    func delete(id: UUID) async throws
}

protocol MemoryRepository: Sendable {
    func all() async throws -> [MemoryItem]
    func insertIfNew(_ item: MemoryItem) async throws -> Bool
    func save(_ item: MemoryItem) async throws
    func delete(id: UUID) async throws
}

protocol ModelCatalog: Sendable {
    func models() async -> [LocalModel]
}

extension MemoryRepository {
    func insertIfNew(_ item: MemoryItem) async throws -> Bool {
        guard try await !all().contains(where: { $0.fingerprint == item.fingerprint }) else { return false }
        try await save(item)
        return true
    }
}
