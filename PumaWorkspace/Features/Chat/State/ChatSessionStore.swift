import Foundation
import Observation

/// Shared chat state for keyboard and voice input. Owns the active
/// conversation, its draft, selection, model, notes, and reply lifecycle.
@MainActor
@Observable
final class ChatSessionStore {
    // MARK: Published state

    private(set) var conversations: [Conversation] = []
    private(set) var activeID: UUID
    private(set) var attachments: [Attachment] = []
    private(set) var models: [LocalModel] = []
    private(set) var memories: [MemoryItem] = []
    /// A memory the assistant proposed and the person has not answered yet.
    private(set) var pendingMemory: MemoryItem?
    /// Fires when a reply stream finishes; voice listens to speak the reply.
    private(set) var lastFinishedReply: Message?

    @ObservationIgnored private let container: AppContainer
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    /// Identifies the current reply stream; events from older streams are dropped.
    @ObservationIgnored private var replyToken = UUID()
    @ObservationIgnored private var replyStarted = Date.now

    init(container: AppContainer) {
        self.container = container
        let blank = Conversation(modelID: Self.fallbackModelID)
        conversations = [blank]
        activeID = blank.id
    }

    private static var fallbackModelID: String {
        #if DEBUG
        Fixtures.defaultModelID
        #else
        ""
        #endif
    }

    /// Loads repositories and opens a fresh chat.
    func load() async {
        let stored = await container.conversations.all()
        attachments = await container.attachments.all()
        models = await container.modelCatalog.models()
        memories = await container.memories.all()
        let defaultModel = models.first { $0.availability == .ready }?.id ?? Self.fallbackModelID
        let blank = Conversation(modelID: defaultModel)
        conversations = [blank] + stored
        activeID = blank.id
    }

    // MARK: Active conversation

    var active: Conversation {
        conversations.first { $0.id == activeID } ?? Conversation(modelID: Self.fallbackModelID)
    }

    private func mutateActive(_ body: (inout Conversation) -> Void) {
        mutate(activeID, body)
    }

    private func mutate(_ id: UUID, _ body: (inout Conversation) -> Void) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        body(&conversations[i])
    }

    var messages: [Message] { active.messages }
    var title: String? { active.title }

    var draft: String {
        get { active.draft }
        set { mutateActive { $0.draft = newValue } }
    }

    var notes: String {
        get { active.notes }
        set { mutateActive { $0.notes = newValue }; persistActive() }
    }

    var selectedSourceIDs: Set<UUID> { active.selectedSourceIDs }
    var hasSelectedSources: Bool { !active.selectedSourceIDs.isEmpty }

    /// What this chat can read: its selected sources, plus anything still importing.
    var chatSources: [Attachment] {
        attachments.filter { $0.readiness != .removed && (isSelected($0.id) || $0.readiness == .importing) }
    }

    /// Takes a source out of this chat. One still importing is discarded.
    func removeFromChat(_ id: UUID) {
        guard let source = attachment(id) else { return }
        if source.readiness == .importing {
            clearAttachment(id)
        } else if isSelected(id) {
            toggleSource(id)
        }
    }

    /// This chat's outputs: the files its replies worked from, in the order
    /// they first appeared.
    var outputs: [Attachment] {
        var seen = Set<UUID>()
        return messages.flatMap(\.documentIDs).compactMap { id in
            seen.insert(id).inserted ? attachment(id) : nil
        }
    }
    var modelID: String { active.modelID }
    var selectedModel: LocalModel? { models.first { $0.id == active.modelID } }

    var isStreaming: Bool { messages.last?.status == .streaming }
    var isEmpty: Bool { messages.isEmpty }

    /// Past chats with at least one message, newest first (drawer).
    var history: [Conversation] {
        conversations.filter { !$0.messages.isEmpty }.sorted {
            // Pinned first, then most recent.
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    // MARK: Chats

    func newChat() {
        if active.messages.isEmpty, active.draft.isEmpty { return }
        cancelReply()
        let fresh = Conversation(modelID: active.modelID)
        conversations.insert(fresh, at: 0)
        activeID = fresh.id
    }

    func select(_ id: UUID) {
        guard id != activeID else { return }
        cancelReply()
        // Drop an untouched blank chat when leaving it.
        if active.messages.isEmpty, active.draft.isEmpty, active.notes.isEmpty {
            conversations.removeAll { $0.id == activeID }
        }
        activeID = id
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(id) { $0.title = trimmed.isEmpty ? nil : trimmed }
        persist(id)
    }

    func togglePin(_ id: UUID) {
        mutate(id) { $0.isPinned.toggle() }
        persist(id)
    }

    func delete(_ id: UUID) {
        if id == activeID {
            cancelReply()
            conversations.removeAll { $0.id == id }
            let fresh = Conversation(modelID: models.first { $0.availability == .ready }?.id ?? Self.fallbackModelID)
            conversations.insert(fresh, at: 0)
            activeID = fresh.id
        } else {
            conversations.removeAll { $0.id == id }
        }
        let repo = container.conversations
        Task { await repo.delete(id: id) }
    }

    // MARK: Sending

    func applySuggestion(_ text: String) { draft = text }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        mutateActive {
            $0.messages.append(Message(role: .user, text: text))
            $0.draft = ""
            if $0.title == nil { $0.title = Self.title(from: text) }
            $0.updatedAt = .now
        }
        startReply(prompt: text)
    }

    func retry() {
        guard let last = messages.last, last.role == .assistant, last.status == .failed,
              let prompt = messages.last(where: { $0.role == .user })?.text else { return }
        mutateActive { $0.messages.removeLast() }
        startReply(prompt: prompt)
    }

    /// Asks for a reply again. The newest reply is replaced; an older one is
    /// asked again at the end of the chat, so nothing after it is lost.
    func regenerate(_ messageID: UUID) {
        guard !isStreaming, let index = messages.firstIndex(where: { $0.id == messageID }),
              let prompt = messages[..<index].last(where: { $0.role == .user })?.text else { return }
        mutateActive {
            if index == $0.messages.count - 1 {
                $0.messages.removeLast()
            } else {
                $0.messages.append(Message(role: .user, text: prompt))
            }
            $0.updatedAt = .now
        }
        startReply(prompt: prompt)
    }

    func stop() {
        guard isStreaming else { return }
        cancelReply()
    }

    private func startReply(prompt: String) {
        cancelReply()
        let conversationID = activeID
        let token = UUID()
        replyToken = token
        let reply = Message(role: .assistant, text: "", modelID: active.modelID, status: .streaming)
        mutateActive { $0.messages.append(reply) }
        let request = ReplyRequest(
            conversationID: conversationID,
            prompt: prompt,
            history: active.messages,
            modelID: active.modelID,
            selectedSourceIDs: active.selectedSourceIDs
        )
        let stream = container.assistant.send(request)
        replyStarted = .now
        replyTask = Task { [weak self] in
            for await event in stream {
                guard let self, self.replyToken == token else { return }
                self.apply(event, to: reply.id, in: conversationID)
            }
        }
    }

    private func apply(_ event: ReplyEvent, to messageID: UUID, in conversationID: UUID) {
        func update(_ body: (inout Message) -> Void) {
            mutate(conversationID) { c in
                guard let i = c.messages.firstIndex(where: { $0.id == messageID }) else { return }
                body(&c.messages[i])
                c.updatedAt = .now
            }
        }
        switch event {
        case .step(let step):
            update { $0.steps.append(step) }
        case .documents(let ids):
            update { $0.documentIDs = ids }
        case .token(let t):
            let worked = max(1, Int(Date.now.timeIntervalSince(replyStarted).rounded()))
            update {
                if $0.text.isEmpty { $0.workSeconds = worked }
                $0.text += t
            }
        case .artifact(let comparison):
            update { $0.artifact = comparison }
        case .memoryProposal(let item):
            pendingMemory = item
        case .failed:
            update { $0.status = .failed }
            persist(conversationID)
        case .finished:
            update { $0.status = .complete }
            persist(conversationID)
            lastFinishedReply = conversations.first { $0.id == conversationID }?.messages.first { $0.id == messageID }
        }
    }

    /// Cancels the reply stream and marks a streaming reply stopped.
    private func cancelReply() {
        replyTask?.cancel()
        replyTask = nil
        replyToken = UUID()
        for ci in conversations.indices {
            for mi in conversations[ci].messages.indices where conversations[ci].messages[mi].status == .streaming {
                conversations[ci].messages[mi].status = .stopped
            }
        }
    }

    // MARK: Sources and model

    func isSelected(_ attachmentID: UUID) -> Bool { active.selectedSourceIDs.contains(attachmentID) }

    func toggleSource(_ attachmentID: UUID) {
        guard let a = attachments.first(where: { $0.id == attachmentID }), a.readiness == .ready else { return }
        mutateActive {
            if $0.selectedSourceIDs.contains(attachmentID) { $0.selectedSourceIDs.remove(attachmentID) }
            else { $0.selectedSourceIDs.insert(attachmentID) }
        }
        persistActive()
    }

    func attachment(_ id: UUID) -> Attachment? { attachments.first { $0.id == id } }

    /// Adds a picked photo or file to this chat. The import itself is
    /// simulated: the card becomes ready shortly after, and nothing is read.
    @discardableResult
    func addAttachment(name: String, kind: Attachment.Kind, thumbnail: Data? = nil, fileURL: URL? = nil) -> UUID {
        let item = Attachment(
            name: name, kind: kind, readiness: .importing,
            previewText: "", thumbnail: thumbnail, fileURL: fileURL
        )
        attachments.append(item)
        finishImport(item.id, selectWhenReady: true)
        return item.id
    }

    func retryAttachment(_ id: UUID) {
        setReadiness(id, .importing)
        finishImport(id)
    }

    /// Clears a removed attachment from the list.
    func clearAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
        for i in conversations.indices { conversations[i].selectedSourceIDs.remove(id) }
        let repo = container.attachments
        Task { await repo.delete(id: id) }
    }

    private func finishImport(_ id: UUID, selectWhenReady: Bool = false) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.attachment(id) != nil else { return }
            self.setReadiness(id, .ready)
            if selectWhenReady, !self.isSelected(id) { self.toggleSource(id) }
        }
    }

    private func setReadiness(_ id: UUID, _ readiness: Attachment.Readiness) {
        guard let i = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[i].readiness = readiness
        let item = attachments[i]
        let repo = container.attachments
        Task { await repo.save(item) }
    }

    func selectModel(_ id: String) {
        guard let m = models.first(where: { $0.id == id }), m.availability == .ready else { return }
        mutateActive { $0.modelID = id }
        persistActive()
    }

    // MARK: Memory

    func saveMemory(text: String) {
        guard var item = pendingMemory else { return }
        item.text = text
        item.state = .saved
        memories.append(item)
        pendingMemory = nil
        let repo = container.memories
        Task { await repo.save(item) }
    }

    func dismissMemory() { pendingMemory = nil }

    func updateMemory(_ id: UUID, text: String) {
        guard let i = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[i].text = text
        let item = memories[i]
        let repo = container.memories
        Task { await repo.save(item) }
    }

    func forgetMemory(_ id: UUID) {
        memories.removeAll { $0.id == id }
        let repo = container.memories
        Task { await repo.delete(id: id) }
    }

    // MARK: Persistence

    private func persistActive() { persist(activeID) }

    private func persist(_ id: UUID) {
        guard let c = conversations.first(where: { $0.id == id }), !c.messages.isEmpty else { return }
        let repo = container.conversations
        Task { await repo.save(c) }
    }

    private static func title(from text: String) -> String {
        let words = text.split(separator: " ").prefix(5).joined(separator: " ")
        return words.count < text.count ? words : text
    }

    // MARK: Debug seeding

    #if DEBUG
    func debugSeed(messages: [Message], draft: String = "", selected: Set<UUID> = [], title: String? = nil) {
        mutateActive {
            $0.messages = messages
            $0.draft = draft
            $0.selectedSourceIDs = selected
            $0.title = title
        }
    }

    func debugProposeMemory(_ item: MemoryItem) { pendingMemory = item }
    #endif
}
