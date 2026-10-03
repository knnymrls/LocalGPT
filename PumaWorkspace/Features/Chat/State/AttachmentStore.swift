import Foundation
import Observation

/// Owns attachment state and import lifetimes. Chat selection remains with the conversation.
@MainActor
@Observable
final class AttachmentStore {
    private(set) var items: [Attachment] = []
    var error: String?
    @ObservationIgnored private let repository: any AttachmentRepository
    @ObservationIgnored private let importer: (any DocumentImporter)?
    @ObservationIgnored private var tasks: [UUID: (generation: UUID, task: Task<Void, Never>)] = [:]

    init(repository: any AttachmentRepository, importer: (any DocumentImporter)?) {
        self.repository = repository
        self.importer = importer
    }

    func load() async throws { items = try await repository.all() }
    func item(_ id: UUID) -> Attachment? { items.first { $0.id == id } }
    func receive(_ item: Attachment) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func prepare(_ item: Attachment, onReady: @escaping @MainActor (Attachment) -> Void) {
        tasks.removeValue(forKey: item.id)?.task.cancel()
        var importing = item
        importing.readiness = .importing
        importing.failureReason = nil
        receive(importing)
        let generation = UUID()
        let importer = importer
        let task = Task { [weak self] in
            defer {
                if self?.tasks[item.id]?.generation == generation { self?.tasks[item.id] = nil }
            }
            do {
                let prepared: Attachment
                if let importer {
                    prepared = try await importer.prepare(importing)
                } else {
                    var fixture = importing
                    fixture.readiness = .ready
                    prepared = fixture
                }
                try Task.checkCancellation()
                guard let self, self.tasks[item.id]?.generation == generation else { return }
                self.receive(prepared)
                onReady(prepared)
            } catch is CancellationError {
            } catch {
                guard let self, self.tasks[item.id]?.generation == generation,
                    let index = self.items.firstIndex(where: { $0.id == item.id })
                else { return }
                self.items[index].readiness = .failed
                self.items[index].failureReason = error.localizedDescription
                self.error = error.localizedDescription
            }
        }
        tasks[item.id] = (generation, task)
    }

    func remove(_ id: UUID) {
        tasks.removeValue(forKey: id)?.task.cancel()
        items.removeAll { $0.id == id }
        let importer = importer
        let repository = repository
        Task { [weak self] in
            do {
                if let importer { try await importer.remove(id) } else { try await repository.delete(id: id) }
            } catch { self?.error = error.localizedDescription }
        }
    }

    deinit { for entry in tasks.values { entry.task.cancel() } }
}
