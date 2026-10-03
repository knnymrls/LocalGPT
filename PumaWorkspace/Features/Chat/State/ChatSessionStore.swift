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
    var operationError: String?
    private(set) var memoryFailure: String?
    @ObservationIgnored private var imports: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var memoryTasks: [UUID: (UUID, Task<Void, Never>)] = [:]
    @ObservationIgnored private var draftSave: Task<Void, Never>?

    @ObservationIgnored private let container: AppContainer
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    /// Identifies the current reply stream; events from older streams are dropped.
    @ObservationIgnored private var replyToken = UUID()
    @ObservationIgnored private var replyStarted = Date.now
    @ObservationIgnored private var checkpointAt = Date.distantPast

    init(container: AppContainer) {
        self.container = container
        let blank = Conversation(modelID: Self.fallbackModelID)
        conversations = [blank]
        activeID = blank.id
    }

    private static var fallbackModelID: String { SystemModelCatalog.modelID }

    func load() async {
        do {
            let stored = try await container.conversations.all()
            attachments = try await container.attachments.all()
            models = await container.modelCatalog.models()
            memories = try await container.memories.all()
            if !stored.isEmpty {
                conversations = stored
                activeID = stored[0].id
            } else {
                let blank = Conversation(modelID: models.first?.id ?? Self.fallbackModelID)
                conversations = [blank]
                activeID = blank.id
            }
            // Reconstruct receipts if the process ended after the memory commit but before the chat snapshot.
            for memory in memories {
                guard let ci = conversations.firstIndex(where: { $0.id == memory.conversationID }),
                      let ui = conversations[ci].messages.firstIndex(where: { $0.id == memory.messageID }),
                      let ai = conversations[ci].messages.indices.dropFirst(ui + 1).first(where: { conversations[ci].messages[$0].role == .assistant }) else { continue }
                if !conversations[ci].messages[ai].savedMemoryIDs.contains(memory.id) {
                    conversations[ci].messages[ai].savedMemoryIDs.append(memory.id)
                    conversations[ci].revision += 1
                    persist(conversations[ci].id)
                }
            }
            for item in attachments where item.readiness == .importing { finishImport(item.id) }
        } catch { operationError = "Could not load your workspace: \(error.localizedDescription)" }
    }

    func refreshAvailability() async { models = await container.modelCatalog.models() }

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
        conversations[i].revision += 1
    }

    var messages: [Message] { active.messages }
    var title: String? { active.title }

    var draft: String {
        get { active.draft }
        set {
            mutateActive { $0.draft = newValue }
            let id = activeID
            draftSave?.cancel()
            draftSave = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                self?.persist(id)
            }
        }
    }

    var notes: String {
        get { active.notes }
        set { mutateActive { $0.notes = newValue }; persistActive() }
    }

    var selectedSourceIDs: Set<UUID> { active.selectedSourceIDs }
    var hasSelectedSources: Bool { !active.selectedSourceIDs.isEmpty }

    /// What this chat can read: its selected sources, plus anything still importing.
    var chatSources: [Attachment] {
        attachments.filter { $0.readiness != .removed && (isSelected($0.id) || ($0.conversationID == activeID && $0.readiness == .importing)) }
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
        persistActive()
        cancelReply()
        let fresh = Conversation(modelID: active.modelID)
        conversations.insert(fresh, at: 0)
        activeID = fresh.id
    }

    func select(_ id: UUID) {
        guard id != activeID, conversations.contains(where: { $0.id == id }) else { return }
        persistActive()
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
        for (key, entry) in memoryTasks where entry.0 == id { entry.1.cancel(); memoryTasks[key] = nil }
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
        Task { do { try await repo.delete(id: id) } catch { operationError = error.localizedDescription } }
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
        persistActive()
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
        var reply = Message(role: .assistant, text: "", modelID: active.modelID, status: .streaming)
        let userMessageID = active.messages.last(where: { $0.role == .user })?.id
        reply.savedMemoryIDs = memories.filter { $0.conversationID == conversationID && $0.messageID == userMessageID }.map(\.id)
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
        guard let service = container.memoryCapture else { return }
        memoryFailure = nil
        let task = Task { [weak self] in
            do {
                try await service.capture(request, scope: RequestScope()) { [weak self] memory in
                    await self?.acceptMemory(memory, replyID: replyID, conversationID: request.conversationID)
                }
            } catch is CancellationError {} catch {
                // Answering remains independent of memory extraction; show a truthful, nonblocking notice.
                self?.memoryFailure = "Memory could not be saved: \(error.localizedDescription)"
            }
            self?.memoryTasks[replyID] = nil
        }
        memoryTasks[replyID] = (request.conversationID, task)
    }

    private func acceptMemory(_ memory: MemoryItem, replyID: UUID, conversationID: UUID) {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else { return }
        let target: UUID?
        if conversation.messages.contains(where: { $0.id == replyID }) { target = replyID }
        else if let origin = conversation.messages.firstIndex(where: { $0.id == memory.messageID }) {
            target = conversation.messages.dropFirst(origin + 1).first(where: { $0.role == .assistant })?.id
        } else { target = nil }
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
            update { if $0.text.isEmpty { $0.workSeconds = worked }; $0.text = text }
            if Date.now.timeIntervalSince(checkpointAt) >= 1 {
                checkpointAt = .now
                persist(conversationID)
            }
        case .memorySaved(let memory):
            if !memories.contains(where: { $0.id == memory.id }) { memories.insert(memory, at: 0) }
            update { if !$0.savedMemoryIDs.contains(memory.id) { $0.savedMemoryIDs.append(memory.id) } }
            persist(conversationID)
        case .output(let file):
            attachments.removeAll { $0.id == file.id }
            attachments.append(file)
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
            update { $0.status = .failed; $0.errorDescription = reason }
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
                conversations[ci].revision += 1
                persist(conversations[ci].id)
            }
        }
    }

    // MARK: Sources and model

    func isSelected(_ attachmentID: UUID) -> Bool { active.selectedSourceIDs.contains(attachmentID) }

    func toggleSource(_ attachmentID: UUID) {
        guard let a = attachments.first(where: { $0.id == attachmentID }), a.readiness == .ready else { return }
        if active.selectedSourceIDs.contains(attachmentID) { cancelReply() }
        mutateActive {
            if $0.selectedSourceIDs.contains(attachmentID) { $0.selectedSourceIDs.remove(attachmentID) }
            else { $0.selectedSourceIDs.insert(attachmentID) }
        }
        persistActive()
    }

    func attachment(_ id: UUID) -> Attachment? { attachments.first { $0.id == id } }

    /// Imports a durable original and indexes its extracted content off the UI actor.
    @discardableResult
    func addAttachment(name: String, kind: Attachment.Kind, thumbnail: Data? = nil, fileURL: URL? = nil, conversationID: UUID? = nil) -> UUID {
        var item = Attachment(
            name: name, kind: kind, readiness: .importing,
            previewText: "", thumbnail: thumbnail, fileURL: fileURL
        )
        item.conversationID = conversationID ?? activeID
        attachments.append(item)
        finishImport(item.id, selectWhenReady: true)
        return item.id
    }

    func retryAttachment(_ id: UUID) {
        setReadiness(id, .importing)
        finishImport(id)
    }

    func clearAttachment(_ id: UUID) {
        imports.removeValue(forKey: id)?.cancel()
        if selectedSourceIDs.contains(id) { cancelReply() }
        attachments.removeAll { $0.id == id }
        for i in conversations.indices where conversations[i].selectedSourceIDs.contains(id) {
            conversations[i].selectedSourceIDs.remove(id)
            conversations[i].revision += 1
            persist(conversations[i].id)
        }
        Task {
            do {
                if let importer = container.importer { try await importer.remove(id) }
                else { try await container.attachments.delete(id: id) }
            } catch { operationError = error.localizedDescription }
        }
    }

    private func finishImport(_ id: UUID, selectWhenReady: Bool = true) {
        guard let item = attachment(id) else { return }
        imports[id]?.cancel()
        imports[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared: Attachment
                if let importer = container.importer { prepared = try await importer.prepare(item) }
                else { var mock = item; mock.readiness = .ready; prepared = mock }
                try Task.checkCancellation()
                guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
                attachments[index] = prepared
                if selectWhenReady, let origin = item.conversationID {
                    mutate(origin) { $0.selectedSourceIDs.insert(id) }
                    persist(origin)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
                attachments[index].readiness = .failed
                attachments[index].failureReason = error.localizedDescription
                operationError = error.localizedDescription
            }
            imports[id] = nil
        }
    }

    private func setReadiness(_ id: UUID, _ readiness: Attachment.Readiness) {
        guard let i = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[i].readiness = readiness
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
            do { try await container.memories.save(item); memories.append(item); pendingMemory = nil }
            catch { operationError = error.localizedDescription }
        }
    }

    func dismissMemory() { pendingMemory = nil }

    func forgetMemory(_ id: UUID) {
        cancelReply() // Revoke any in-flight prompt containing the forgotten fact.
        for entry in memoryTasks.values { entry.1.cancel() }; memoryTasks.removeAll()
        Task {
            do { try await container.memories.delete(id: id); memories.removeAll { $0.id == id } }
            catch { operationError = error.localizedDescription }
        }
    }

    // MARK: Persistence

    func flush() { draftSave?.cancel(); persistActive() }
    private func persistActive() { persist(activeID) }

    private func persist(_ id: UUID) {
        guard let c = conversations.first(where: { $0.id == id }) else { return }
        let repo = container.conversations
        Task { do { try await repo.save(c) } catch { operationError = "Could not save changes: \(error.localizedDescription)" } }
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
