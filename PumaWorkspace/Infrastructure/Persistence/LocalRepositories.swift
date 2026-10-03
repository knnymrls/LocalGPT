import Foundation

struct LocalConversationRepository: ConversationRepository {
    let database: WorkspaceDatabase
    func all() async throws -> [Conversation] {
        var records = try await database.readAll(.conversations, as: Conversation.self)
        for i in records.indices {
            for j in records[i].messages.indices where records[i].messages[j].status == .streaming {
                records[i].messages[j].status = .stopped
            }
        }
        return records.sorted { $0.updatedAt > $1.updatedAt }
    }
    func save(_ conversation: Conversation) async throws {
        try await database.save(conversation, id: conversation.id, in: .conversations, revision: conversation.revision)
    }
    func delete(id: UUID) async throws { try await database.delete(id, from: .conversations) }
}

struct LocalAttachmentRepository: AttachmentRepository {
    let database: WorkspaceDatabase
    func all() async throws -> [Attachment] { try await database.readAll(.attachments, as: Attachment.self) }
    func save(_ attachment: Attachment) async throws {
        let committed = try await database.save(attachment, id: attachment.id, in: .attachments)
        guard committed else { throw CancellationError() }
    }
    func delete(id: UUID) async throws { try await database.delete(id, from: .attachments) }
}

struct LocalMemoryRepository: MemoryRepository {
    let database: WorkspaceDatabase
    func all() async throws -> [MemoryItem] { try await database.readAll(.memories, as: MemoryItem.self).filter { $0.state == .saved } }
    func insertIfNew(_ item: MemoryItem) async throws -> Bool { try await database.insertMemoryIfNew(item) }
    func save(_ item: MemoryItem) async throws {
        let committed = try await database.save(item, id: item.id, in: .memories, revision: Int(item.updatedAt.timeIntervalSince1970 * 1_000_000))
        guard committed else { throw CancellationError() }
    }
    func delete(id: UUID) async throws { try await database.delete(id, from: .memories) }
}
