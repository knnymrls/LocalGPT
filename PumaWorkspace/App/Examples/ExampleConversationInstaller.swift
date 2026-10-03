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
            let installedAt = Date.now
            for (index, example) in ExampleConversation.catalog.enumerated() {
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
                    selectedSourceIDs: Set(output.map { [$0.id] } ?? []),
                    modelID: SystemModelCatalog.modelID,
                    notes: "This chat begins with an authored, fictional example. Sample details are not facts about the person. Do not save example details to memory. Subsequent questions are live requests.")
                conversation.exampleID = example.id.uuidString
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
