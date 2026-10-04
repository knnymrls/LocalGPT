import Foundation

/// Owns extraction task lifetimes without owning chat presentation or persistence.
@MainActor
final class MemoryCaptureCoordinator {
    private struct Entry {
        let conversationID: UUID
        let generation: UUID
        let task: Task<Void, Never>
    }
    private let service: (any MemoryCapture)?
    private var tasks: [UUID: Entry] = [:]

    init(service: (any MemoryCapture)?) { self.service = service }

    func capture(
        _ request: ReplyRequest, replyID: UUID,
        onSaved: @escaping @MainActor (MemoryItem) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        guard let service else { return }
        tasks[replyID]?.task.cancel()
        let generation = UUID()
        let task = Task { [weak self] in
            defer {
                if self?.tasks[replyID]?.generation == generation { self?.tasks[replyID] = nil }
            }
            do {
                try await service.capture(request) { [weak self] item in
                    await self?.deliver(item, replyID: replyID, generation: generation, onSaved: onSaved)
                }
            } catch is CancellationError {
            } catch {
                guard self?.tasks[replyID]?.generation == generation, !Task.isCancelled else { return }
                onFailure(error.localizedDescription)
            }
        }
        tasks[replyID] = Entry(conversationID: request.conversationID, generation: generation, task: task)
    }

    private func deliver(
        _ item: MemoryItem, replyID: UUID, generation: UUID,
        onSaved: @MainActor (MemoryItem) -> Void
    ) {
        guard tasks[replyID]?.generation == generation, !Task.isCancelled else { return }
        onSaved(item)
    }

    func cancel(conversationID: UUID? = nil) {
        let ids = tasks.filter { conversationID == nil || $0.value.conversationID == conversationID }.map(\.key)
        for id in ids { tasks.removeValue(forKey: id)?.task.cancel() }
    }

    deinit { for entry in tasks.values { entry.task.cancel() } }
}
