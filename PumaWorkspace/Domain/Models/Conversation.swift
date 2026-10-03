import Foundation

struct Conversation: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String?
    var createdAt: Date
    var updatedAt: Date
    var messages: [Message]
    var draft: String
    var selectedSourceIDs: Set<UUID>
    var modelID: String
    var notes: String
    /// Pinned chats stay at the top of the drawer.
    var isPinned: Bool = false
    var revision: Int = 0
    /// Present only for authored onboarding examples; optional for older stored chats.
    var exampleID: String? = nil
    var exampleVersion: Int? = nil

    init(
        id: UUID = UUID(),
        title: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [Message] = [],
        draft: String = "",
        selectedSourceIDs: Set<UUID> = [],
        modelID: String,
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.draft = draft
        self.selectedSourceIDs = selectedSourceIDs
        self.modelID = modelID
        self.notes = notes
    }
}

struct Message: Identifiable, Hashable, Codable, Sendable {
    enum Role: Codable, Sendable { case user, assistant }
    enum Status: Codable, Sendable { case complete, streaming, stopped, failed }

    let id: UUID
    var role: Role
    var text: String
    var modelID: String?
    var status: Status
    var artifact: Comparison?
    /// What the assistant did before answering, in order.
    var steps: [String]
    /// How long that work took, once the answer began.
    var workSeconds: Int?
    /// The sources the reply drew on, shown at its end.
    var documentIDs: [UUID]
    var savedMemoryIDs: [UUID] = []
    var citations: [Citation] = []
    var errorDescription: String?
    var createdAt: Date = .now

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        modelID: String? = nil,
        status: Status = .complete,
        artifact: Comparison? = nil,
        steps: [String] = [],
        workSeconds: Int? = nil,
        documentIDs: [UUID] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.modelID = modelID
        self.status = status
        self.artifact = artifact
        self.steps = steps
        self.workSeconds = workSeconds
        self.documentIDs = documentIDs
    }
}
