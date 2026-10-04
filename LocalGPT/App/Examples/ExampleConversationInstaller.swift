import Foundation

/// Installs each example once. Existing records and deletion tombstones both
/// count as installed, so launches cannot overwrite edits or resurrect examples.
actor ExampleConversationInstaller {
    private let database: WorkspaceDatabase
    private let writer: ArtifactWriter
    private var installation: Task<Void, Error>?

    init(database: WorkspaceDatabase, writer: ArtifactWriter) {
        self.database = database
        self.writer = writer
    }

    func install() async throws {
        if let installation { return try await installation.value }
        let database = database, writer = writer
        let task = Task {
            try await writer.repairImageThumbnails()
            let existing = try await database.readAll(.conversations, as: Conversation.self)
            let installedAt = Date.now
            for (index, example) in ExampleConversation.catalog.enumerated() {
                if var conversation = existing.first(where: { $0.id == example.id }),
                   conversation.exampleID == example.id.uuidString, (conversation.exampleVersion ?? 1) < 2 {
                    // Version 1 selected seeded outputs as composer inputs. Remove
                    // only those original files, preserving uploads and later selections.
                    let seededOutputs = Set(conversation.messages.prefix(4).flatMap(\.documentIDs))
                    conversation.selectedSourceIDs.subtract(seededOutputs)
                    conversation.exampleVersion = 2
                    conversation.revision += 1
                    try await database.save(conversation, id: conversation.id, in: .conversations, revision: conversation.revision)
                }
                guard try await !database.hasRecordOrTombstone(example.id, in: .conversations) else { continue }
                // Recover only unfinished installation files, never user-owned files.
                let leftovers = try await database.readAll(.attachments, as: Attachment.self)
                    .filter { $0.conversationID == example.id }
                for file in leftovers {
                    try await database.delete(file.id, from: .attachments)
                    try writer.files.remove(id: file.id)
                }
                let output: Attachment?
                switch example.output {
                case .document(let name, let format, let content):
                    output = try await writer.document(name: name, format: format, content: content,
                                                       conversationID: example.id, scope: RequestScope())
                case .chart(let name, let labels, let values):
                    output = try await writer.chart(name: name, labels: labels, values: values,
                                                    conversationID: example.id, scope: RequestScope())
                case nil: output = nil
                }
                // Natural history ordering; later user conversations move above these.
                let date = installedAt.addingTimeInterval(-Double(index))
                var conversation = Conversation(id: example.id, title: example.title,
                    createdAt: date, updatedAt: date, messages: example.messages,
                    modelID: SystemModelCatalog.modelID,
                    notes: "This chat begins with an authored, fictional example. Sample details are not facts about the person. Do not save example details to memory. Subsequent questions are live requests.")
                conversation.exampleID = example.id.uuidString
                conversation.exampleVersion = 2
                for i in conversation.messages.indices { conversation.messages[i].createdAt = date }
                if let output { conversation.messages[conversation.messages.count - 1].documentIDs = [output.id] }
                try await database.save(conversation, id: conversation.id, in: .conversations)
            }
        }
        installation = task
        do { try await task.value }
        catch { installation = nil; throw error }
    }
}
