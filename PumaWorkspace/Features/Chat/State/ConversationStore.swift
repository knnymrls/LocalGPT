import Foundation
import Observation

/// Owns conversation selection, revisions, and durable snapshots. It has no model or audio dependency.
@MainActor
@Observable
final class ConversationStore {
    private(set) var items: [Conversation]
    private(set) var activeID: UUID
    var error: String?
    @ObservationIgnored private let repository: any ConversationRepository
    @ObservationIgnored private let defaultModelID: String
    @ObservationIgnored private var draftSave: Task<Void, Never>?

    init(repository: any ConversationRepository, defaultModelID: String) {
        self.repository = repository
        self.defaultModelID = defaultModelID
        let blank = Conversation(modelID: defaultModelID)
        items = [blank]
        activeID = blank.id
    }

    var active: Conversation {
        // All selection/deletion operations preserve one active record.
        items.first { $0.id == activeID } ?? items[0]
    }

    var history: [Conversation] {
        items.filter { !$0.messages.isEmpty }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var draft: String {
        get { active.draft }
        set {
            mutate(activeID) { $0.draft = newValue }
            let id = activeID
            draftSave?.cancel()
            draftSave = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                self?.persist(id)
            }
        }
    }

    func load() async throws {
        let stored = try await repository.all()
        if let recent = stored.first(where: { $0.exampleID == nil || $0.revision > 0 }) {
            items = stored
            activeID = recent.id
        } else {
            let blank = Conversation(modelID: defaultModelID)
            items = [blank] + stored
            activeID = blank.id
        }
    }

    func mutate(_ id: UUID, _ body: (inout Conversation) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[index])
        items[index].revision += 1
    }

    func create() {
        let blank = Conversation(modelID: active.modelID)
        items.insert(blank, at: 0)
        activeID = blank.id
    }

    func select(_ id: UUID) {
        guard id != activeID, items.contains(where: { $0.id == id }) else { return }
        if active.messages.isEmpty, active.draft.isEmpty, active.notes.isEmpty,
            active.selectedSourceIDs.isEmpty, active.draftSourceIDs?.isEmpty != false
        {
            items.removeAll { $0.id == activeID }
        }
        activeID = id
    }

    func delete(_ id: UUID, replacementModelID: String) {
        if id == activeID {
            let blank = Conversation(modelID: replacementModelID)
            items.insert(blank, at: 0)
            activeID = blank.id
        }
        items.removeAll { $0.id == id }
        let repository = repository
        Task { [weak self] in
            do { try await repository.delete(id: id) } catch { self?.error = error.localizedDescription }
        }
    }

    func stopStreamingReplies() {
        for conversation in items where conversation.messages.contains(where: { $0.status == .streaming }) {
            mutate(conversation.id) { conversation in
                for index in conversation.messages.indices where conversation.messages[index].status == .streaming {
                    conversation.messages[index].status = .stopped
                }
            }
            persist(conversation.id)
        }
    }

    func restoreMemoryReceipts(_ memories: [MemoryItem]) {
        for memory in memories {
            guard let conversation = items.first(where: { $0.id == memory.conversationID }),
                let origin = conversation.messages.firstIndex(where: { $0.id == memory.messageID }),
                let target = conversation.messages.indices.dropFirst(origin + 1).first(where: {
                    conversation.messages[$0].role == .assistant
                }),
                !conversation.messages[target].savedMemoryIDs.contains(memory.id)
            else { continue }
            mutate(conversation.id) { $0.messages[target].savedMemoryIDs.append(memory.id) }
            persist(conversation.id)
        }
    }

    func removeSource(_ id: UUID) {
        for conversation in items
        where conversation.selectedSourceIDs.contains(id) || conversation.draftSourceIDs?.contains(id) == true {
            mutate(conversation.id) {
                $0.selectedSourceIDs.remove(id)
                $0.draftSourceIDs?.remove(id)
            }
            persist(conversation.id)
        }
    }

    func flush() {
        draftSave?.cancel()
        persist(activeID)
    }

    func persist(_ id: UUID) {
        guard let snapshot = items.first(where: { $0.id == id }) else { return }
        let repository = repository
        Task { [weak self] in
            do { try await repository.save(snapshot) } catch {
                self?.error = "Could not save changes: \(error.localizedDescription)"
            }
        }
    }

    deinit { draftSave?.cancel() }
}
