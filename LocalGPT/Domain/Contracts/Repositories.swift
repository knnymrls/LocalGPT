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
    /// Check the fingerprint and insert atomically; report true only after committing.
    func insertIfNew(_ item: MemoryItem) async throws -> Bool
    func save(_ item: MemoryItem) async throws
    func delete(id: UUID) async throws
}

protocol ModelCatalog: Sendable {
    var defaultModelID: String { get }
    func models() async -> [LocalModel]
}
