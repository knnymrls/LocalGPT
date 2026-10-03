import Foundation

protocol ConversationRepository: Sendable {
    func all() async -> [Conversation]
    func save(_ conversation: Conversation) async
    func delete(id: UUID) async
}

protocol AttachmentRepository: Sendable {
    func all() async -> [Attachment]
    func save(_ attachment: Attachment) async
    func delete(id: UUID) async
}

protocol MemoryRepository: Sendable {
    func all() async -> [MemoryItem]
    func save(_ item: MemoryItem) async
    func delete(id: UUID) async
}

protocol ModelCatalog: Sendable {
    func models() async -> [LocalModel]
}
