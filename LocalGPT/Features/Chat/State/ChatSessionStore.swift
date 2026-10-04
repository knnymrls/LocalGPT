import Foundation
import Observation

/// Shared chat state for keyboard and voice input. Owns the active
/// conversation, its draft, selection, model, notes, and reply lifecycle.
@MainActor
@Observable
final class ChatSessionStore {
    // MARK: Published state

    let conversationStore: ConversationStore
    var conversations: [Conversation] { conversationStore.items }
    var activeID: UUID { conversationStore.activeID }
    var attachments: [Attachment] { attachmentStore.items }
    let attachmentStore: AttachmentStore
    private(set) var models: [LocalModel] = []
    private(set) var memories: [MemoryItem] = []
    /// A memory the assistant proposed and the person has not answered yet.
    private(set) var pendingMemory: MemoryItem?
    /// Fires when a reply stream finishes; voice listens to speak the reply.
    private(set) var lastFinishedReply: Message?
    var operationError: String?
    private(set) var memoryFailure: String?
    @ObservationIgnored private let memoryCapture: MemoryCaptureCoordinator

    @ObservationIgnored private let container: AppContainer
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    /// Identifies the current reply stream; events from older streams are dropped.
    @ObservationIgnored private var replyToken = UUID()
    @ObservationIgnored private var replyStarted = Date.now
    @ObservationIgnored private var checkpointAt = Date.distantPast

    init(container: AppContainer) {
        self.container = container
        attachmentStore = AttachmentStore(repository: container.attachments, importer: container.importer)
        memoryCapture = MemoryCaptureCoordinator(service: container.memoryCapture)
        conversationStore = ConversationStore(
            repository: container.conversations, defaultModelID: container.modelCatalog.defaultModelID)
    }

    func load() async {
        do { try await container.prepareExamples?() } catch {
            operationError = "Could not prepare chats: \(error.localizedDescription)"
        }
        do {
            try await conversationStore.load()
            try await attachmentStore.load()
            models = await container.modelCatalog.models()
            memories = try await container.memories.all()
            conversationStore.restoreMemoryReceipts(memories)
            for item in attachments where item.readiness == .importing { finishImport(item.id) }
        } catch { operationError = "Could not load your workspace: \(error.localizedDescription)" }
    }

    func refreshAvailability() async { models = await container.modelCatalog.models() }

    // MARK: Active conversation

    var active: Conversation { conversationStore.active }

    private func mutateActive(_ body: (inout Conversation) -> Void) { mutate(activeID, body) }
    private func mutate(_ id: UUID, _ body: (inout Conversation) -> Void) { conversationStore.mutate(id, body) }

    var messages: [Message] { active.messages }
    var isPreview: Bool { container.isPreview }
    var title: String? { active.title }

    var draft: String {
        get { conversationStore.draft }
        set { conversationStore.draft = newValue }
    }

    var notes: String {
        get { active.notes }
        set {
            mutateActive { $0.notes = newValue }
            persistActive()
        }
    }

    var selectedSourceIDs: Set<UUID> { active.selectedSourceIDs }
    var hasSelectedSources: Bool { !active.selectedSourceIDs.isEmpty }

    /// Pending inputs are distinct from the sources retained for follow-up questions.
    private var draftSourceIDs: Set<UUID> {
        active.draftSourceIDs ?? active.selectedSourceIDs.subtracting(Set(messages.flatMap(\.documentIDs)))
    }

    /// Only unsent inputs appear in the composer.
    var chatSources: [Attachment] {
        attachments.filter {
            $0.readiness != .removed
                && (draftSourceIDs.contains($0.id) || ($0.conversationID == activeID && $0.readiness == .importing))
        }
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
        let generated = attachments.filter { $0.isGenerated && $0.conversationID == activeID }.map(\.id)
        return (messages.flatMap(\.documentIDs) + generated).compactMap { id in
            seen.insert(id).inserted ? attachment(id) : nil
        }
    }
    var chatMemories: [MemoryItem] { memories.filter { $0.conversationID == activeID } }
    var outputCount: Int { outputs.count + chatMemories.count }
    var modelID: String { active.modelID }
    var selectedModel: LocalModel? { models.first { $0.id == active.modelID } }

    var isStreaming: Bool { messages.last?.status == .streaming }
    var isEmpty: Bool { messages.isEmpty }

    /// Past chats with at least one message, newest first (drawer).
    var history: [Conversation] { conversationStore.history }

    // MARK: Chats

    func newChat() {
        if active.messages.isEmpty, active.draft.isEmpty, chatSources.isEmpty { return }
        persistActive()
        cancelReply()
        conversationStore.create()
    }

    func select(_ id: UUID) {
        guard id != activeID, conversations.contains(where: { $0.id == id }) else { return }
        persistActive()
        cancelReply()
        conversationStore.select(id)
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
        memoryCapture.cancel(conversationID: id)
        if id == activeID { cancelReply() }
        conversationStore.delete(
            id,
            replacementModelID: models.first { $0.availability == .ready }?.id ?? container.modelCatalog.defaultModelID)
    }

    // MARK: Sending

    func send() {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = chatSources
        guard !typed.isEmpty || !pending.isEmpty, !isStreaming else { return }
        guard !pending.contains(where: { $0.readiness == .importing }) else {
            operationError = "Your attachment is still preparing. Please send again when it is ready."
            return
        }
        guard !pending.contains(where: { $0.readiness == .failed }) else {
            operationError = "An attachment could not be read. Remove it or retry its import before sending."
            return
        }
        let text = typed.isEmpty ? "What is in this attachment?" : typed
        mutateActive {
            $0.messages.append(Message(role: .user, text: text, documentIDs: pending.map(\.id)))
            $0.draftSourceIDs = []
            $0.draft = ""
            if $0.title == nil { $0.title = Self.title(from: text) }
            $0.updatedAt = .now
        }
        persistActive()
        startReply(prompt: text)
    }

    func retry() {
        guard let last = messages.last, last.role == .assistant, last.status == .failed,
            let prompt = messages.last(where: { $0.role == .user })?.text
        else { return }
        mutateActive { $0.messages.removeLast() }
        startReply(prompt: prompt)
    }

    /// Asks for a reply again. The newest reply is replaced; an older one is
    /// asked again at the end of the chat, so nothing after it is lost.
    func regenerate(_ messageID: UUID) {
        guard !isStreaming, let index = messages.firstIndex(where: { $0.id == messageID }),
            let prompt = messages[..<index].last(where: { $0.role == .user })?.text
        else { return }
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
        var reply = Message(role: .assistant, text: "", modelID: active.modelID, status: .streaming)
        let userMessageID = active.messages.last(where: { $0.role == .user })?.id
        reply.savedMemoryIDs = memories.filter { $0.conversationID == conversationID && $0.messageID == userMessageID }
            .map(\.id)
        mutateActive { $0.messages.append(reply) }
        let request = ReplyRequest(
            conversationID: conversationID,
            prompt: prompt,
            history: active.messages,
            modelID: active.modelID,
            selectedSourceIDs: active.selectedSourceIDs,
            userMessageID: userMessageID,
            notes: active.notes
        )
        persistActive()
        captureMemories(request, replyID: reply.id)
        let stream = container.assistant.send(request)
        replyStarted = .now
        replyTask = Task { [weak self] in
            for await event in stream {
                guard let self, self.replyToken == token else { return }
                self.apply(event, to: reply.id, in: conversationID)
            }
        }
    }

    private func captureMemories(_ request: ReplyRequest, replyID: UUID) {
        memoryFailure = nil
        memoryCapture.capture(request, replyID: replyID) { [weak self] memory in
            self?.acceptMemory(memory, replyID: replyID, conversationID: request.conversationID)
        } onFailure: { [weak self] reason in
            self?.memoryFailure = "Memory could not be saved: \(reason)"
        }
    }

    private func acceptMemory(_ memory: MemoryItem, replyID: UUID, conversationID: UUID) {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        let target: UUID?
        if conversation.messages.contains(where: { $0.id == replyID }) {
            target = replyID
        } else if let origin = conversation.messages.firstIndex(where: { $0.id == memory.messageID }) {
            target = conversation.messages.dropFirst(origin + 1).first(where: { $0.role == .assistant })?.id
        } else {
            target = nil
        }
        guard let target else { return }
        apply(.memorySaved(memory), to: target, in: conversationID)
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
            update { $0.documentIDs = Array(Set($0.documentIDs + ids)).sorted { $0.uuidString < $1.uuidString } }
        case .text(let text):
            let worked = max(1, Int(Date.now.timeIntervalSince(replyStarted).rounded()))
            update {
                if $0.text.isEmpty { $0.workSeconds = worked }
                $0.text = text
            }
            if Date.now.timeIntervalSince(checkpointAt) >= 1 {
                checkpointAt = .now
                persist(conversationID)
            }
        case .memorySaved(let memory):
            if !memories.contains(where: { $0.id == memory.id }) { memories.insert(memory, at: 0) }
            update { if !$0.savedMemoryIDs.contains(memory.id) { $0.savedMemoryIDs.append(memory.id) } }
            persist(conversationID)
        case .output(let file):
            attachmentStore.receive(file)
            update { if !$0.documentIDs.contains(file.id) { $0.documentIDs.append(file.id) } }
            persist(conversationID)
        case .citations(let citations):
            update { $0.citations = citations }
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
        case .failed(let reason):
            update {
                $0.status = .failed
                $0.errorDescription = reason
            }
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
        conversationStore.stopStreamingReplies()
    }

    // MARK: Sources and model

    func isSelected(_ attachmentID: UUID) -> Bool { active.selectedSourceIDs.contains(attachmentID) }

    func toggleSource(_ attachmentID: UUID) {
        guard let a = attachments.first(where: { $0.id == attachmentID }), a.readiness == .ready else { return }
        if active.selectedSourceIDs.contains(attachmentID) { cancelReply() }
        let pending = draftSourceIDs
        mutateActive {
            $0.draftSourceIDs = pending
            if $0.selectedSourceIDs.contains(attachmentID) {
                $0.selectedSourceIDs.remove(attachmentID)
                $0.draftSourceIDs?.remove(attachmentID)
            } else {
                $0.selectedSourceIDs.insert(attachmentID)
                $0.draftSourceIDs?.insert(attachmentID)
            }
        }
        persistActive()
    }

    func attachment(_ id: UUID) -> Attachment? { attachments.first { $0.id == id } }

    /// Imports a durable original and indexes its extracted content off the UI actor.
    @discardableResult
    func addAttachment(
        name: String, kind: Attachment.Kind, thumbnail: Data? = nil, fileURL: URL? = nil, conversationID: UUID? = nil
    ) -> UUID {
        var item = Attachment(
            name: name, kind: kind, readiness: .importing,
            previewText: "", thumbnail: thumbnail, fileURL: fileURL
        )
        let origin = conversationID ?? activeID
        item.conversationID = origin
        mutate(origin) {
            if $0.draftSourceIDs == nil {
                $0.draftSourceIDs = $0.selectedSourceIDs.subtracting(Set($0.messages.flatMap(\.documentIDs)))
            }
            $0.draftSourceIDs?.insert(item.id)
        }
        persist(origin)
        prepareAttachment(item)
        return item.id
    }

    func retryAttachment(_ id: UUID) {
        finishImport(id)
    }

    func clearAttachment(_ id: UUID) {
        if selectedSourceIDs.contains(id) { cancelReply() }
        attachmentStore.remove(id)
        conversationStore.removeSource(id)
    }

    private func finishImport(_ id: UUID) {
        guard let item = attachment(id) else { return }
        prepareAttachment(item)
    }

    private func prepareAttachment(_ item: Attachment) {
        attachmentStore.prepare(item) { [weak self] prepared in
            guard let self, let origin = prepared.conversationID else { return }
            self.mutate(origin) { $0.selectedSourceIDs.insert(prepared.id) }
            self.persist(origin)
        }
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
        Task {
            do {
                try await container.memories.save(item)
                memories.append(item)
                pendingMemory = nil
            } catch { operationError = error.localizedDescription }
        }
    }

    func dismissMemory() { pendingMemory = nil }

    func forgetMemory(_ id: UUID) {
        cancelReply()  // Revoke any in-flight prompt containing the forgotten fact.
        memoryCapture.cancel()
        Task {
            do {
                try await container.memories.delete(id: id)
                memories.removeAll { $0.id == id }
            } catch { operationError = error.localizedDescription }
        }
    }

    // MARK: Persistence

    func flush() { conversationStore.flush() }
    private func persistActive() { persist(activeID) }
    private func persist(_ id: UUID) { conversationStore.persist(id) }

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
