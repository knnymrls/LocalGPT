import XCTest

@testable import LocalGPT

@MainActor
final class CoordinationTests: XCTestCase {
    func testMemoryRepositoryDeduplicatesConcurrentInserts() async {
        let repository = InMemoryMemoryRepository([])
        let item = MemoryItem(text: "I prefer quiet rooms", origin: "test", state: .saved)
        async let first = repository.insertIfNew(item)
        async let second = repository.insertIfNew(item)
        let results = await [first, second]
        let saved = await repository.all()
        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(saved.count, 1)
    }

    func testFinishingImportPreservesAttachmentOrder() async {
        let store = AttachmentStore(repository: InMemoryAttachmentRepository([]), importer: nil)
        let first = Attachment(name: "first.txt", kind: .text, readiness: .importing)
        let second = Attachment(name: "second.txt", kind: .text, readiness: .importing)
        store.receive(first)
        store.receive(second)
        var ready = first
        ready.readiness = .ready
        store.receive(ready)
        XCTAssertEqual(store.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(store.items.first?.readiness, .ready)
    }

    func testReplacingImportRejectsLateFailureAndKeepsNewResult() async throws {
        let importer = SuspendedImporter()
        let store = AttachmentStore(repository: InMemoryAttachmentRepository([]), importer: importer)
        let file = Attachment(name: "notes.txt", kind: .document, readiness: .importing, previewText: "")
        var ready: [Attachment] = []
        store.prepare(file) { ready.append($0) }
        await waitUntil { await importer.count == 1 }
        store.prepare(file) { ready.append($0) }
        await waitUntil { await importer.count == 2 }
        await importer.fail(0)
        await importer.finish(1, item: file)
        await waitUntil { ready.count == 1 }
        XCTAssertNil(store.error)
        XCTAssertEqual(store.item(file.id)?.readiness, .ready)
        XCTAssertEqual(ready.count, 1)
    }

    func testRemovingImportRejectsLateCompletion() async throws {
        let importer = SuspendedImporter()
        let store = AttachmentStore(repository: InMemoryAttachmentRepository([]), importer: importer)
        let file = Attachment(name: "notes.txt", kind: .document, readiness: .importing, previewText: "")
        var delivered = false
        store.prepare(file) { _ in delivered = true }
        await waitUntil { await importer.count == 1 }
        store.remove(file.id)
        await importer.finish(0, item: file)
        await waitUntil { await importer.completed == 1 }
        await Task.yield()
        XCTAssertNil(store.item(file.id))
        XCTAssertFalse(delivered)
    }

    func testMemoryReplacementAndCancellationRejectLateReceipts() async throws {
        let service = SuspendedMemoryCapture()
        let coordinator = MemoryCaptureCoordinator(service: service)
        let request = ReplyRequest(
            conversationID: UUID(), prompt: "Remember this", history: [], modelID: "test", selectedSourceIDs: [])
        let reply = UUID()
        var delivered: [String] = []
        var failures: [String] = []
        coordinator.capture(
            request, replyID: reply, onSaved: { delivered.append($0.text) }, onFailure: { failures.append($0) })
        await waitUntil { await service.count == 1 }
        coordinator.capture(
            request, replyID: reply, onSaved: { delivered.append($0.text) }, onFailure: { failures.append($0) })
        await waitUntil { await service.count == 2 }
        await service.finish(0, text: "obsolete")
        await service.finish(1, text: "current")
        await waitUntil { delivered == ["current"] }
        coordinator.capture(
            request, replyID: UUID(), onSaved: { delivered.append($0.text) }, onFailure: { failures.append($0) })
        await waitUntil { await service.count == 3 }
        coordinator.cancel(conversationID: request.conversationID)
        await service.finish(2, text: "canceled")
        await waitUntil { await service.completed == 3 }
        XCTAssertEqual(delivered, ["current"])
        XCTAssertTrue(failures.isEmpty)
    }

    func testOutputRevisionUsesRecentIntentWithoutLeakingIntoOrdinaryChat() {
        let previous = Message(role: .user, text: "Create a bar chart of attendance")
        func policy(_ text: String, history: [Message] = [previous]) -> ToolPolicy {
            let current = Message(role: .user, text: text)
            return ToolPolicy(
                request: ReplyRequest(
                    conversationID: UUID(), prompt: text,
                    history: history + [current], modelID: "test", selectedSourceIDs: [], userMessageID: current.id))
        }
        XCTAssertTrue(policy("Revise it with Friday at 12").charts)
        XCTAssertFalse(policy("Thanks, how are you?").charts)
        XCTAssertFalse(policy("Do not recreate it").charts)
        XCTAssertFalse(
            policy(
                "Revise it with Friday at 12", history: [previous, Message(role: .user, text: "Tell me about birds")]
            ).charts)
        XCTAssertTrue(ToolPolicy(prompt: "Plot these numbers as a graph").charts)
        XCTAssertTrue(ToolPolicy(prompt: "Write analysis.r").files)
        XCTAssertFalse(ToolPolicy(prompt: "Don't create a PDF").files)
        XCTAssertFalse(ToolPolicy(prompt: "Do not revise that PDF").files)
    }

    func testConversationalFileRequestsAndFormatCorrections() {
        let previous = Message(role: .user, text: "Can you make a PDF about checks and balances?")
        func policy(_ text: String) -> ToolPolicy {
            let current = Message(role: .user, text: text)
            return ToolPolicy(request: ReplyRequest(conversationID: UUID(), prompt: text,
                history: [previous, current], modelID: "test", selectedSourceIDs: [], userMessageID: current.id))
        }
        XCTAssertEqual(policy("Txt I meant").fileFormat, "txt")
        XCTAssertEqual(policy("Well can u give it to me in a file?").fileFormat, "txt")
        XCTAssertEqual(policy("Can you put this in a PDF?").fileFormat, "pdf")
        XCTAssertEqual(policy("Export this as Markdown").fileFormat, "md")
        XCTAssertFalse(policy("What is a PDF?").files)
        XCTAssertFalse(policy("Thanks!").files)
        XCTAssertFalse(policy("Don’t create a PDF").files)
        XCTAssertFalse(policy("Don't send it as a file").files)
        XCTAssertFalse(ToolPolicy(prompt: "Txt I meant").files, "A correction needs a preceding file request")
    }

    func testExportPreservesAnswerInsteadOfSavingCapabilityRefusal() {
        let answer = Message(role: .assistant, text: "Each transaction records matching debits and credits.")
        let refusal = Message(role: .assistant, text: "I cannot create a PDF for you.")
        let request = ReplyRequest(conversationID: UUID(), prompt: "Txt I meant", history: [answer, refusal],
                                   modelID: "test", selectedSourceIDs: [])
        XCTAssertEqual(DocumentResponder.exportContent(for: request), answer.text)
        var revision = request
        revision.prompt = "Put that in a PDF and add a second example"
        XCTAssertNil(DocumentResponder.exportContent(for: revision))
    }

    func testExplicitTablePresentationRespectsNegation() {
        XCTAssertTrue(SourceAnswer.requestsTable("Compare these in a table"))
        XCTAssertTrue(SourceAnswer.requestsTable("Use a tabular comparison"))
        XCTAssertFalse(SourceAnswer.requestsTable("Is this stable?"))
        XCTAssertFalse(SourceAnswer.requestsTable("Compare these without a table"))
        XCTAssertFalse(SourceAnswer.requestsTable("Don't use a table"))
    }

    func testImageInputRejectsMissingAndExcessImages() async throws {
        guard #available(iOS 27.0, *) else { return }
        let missing = Attachment(name: "missing.jpg", kind: .image, readiness: .ready)
        for images in [[missing], Array(repeating: missing, count: 5)] {
            do {
                _ = try await ImageInputSupport.prompt(text: "Describe", images: images, model: .default, tools: [])
                XCTFail("Missing and excessive image input must fail explicitly")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(images.count > 4 ? "four images" : "could not be opened"))
            }
        }
    }

    func testImageCapabilityNoticeDoesNotInterceptTextOrGeneralQuestions() {
        XCTAssertTrue(ImageInputSupport.needsVisualUnderstanding("What's this?"))
        XCTAssertTrue(ImageInputSupport.needsVisualUnderstanding("What is in this attachment?"))
        XCTAssertTrue(ImageInputSupport.needsVisualUnderstanding("Describe the photo"))
        XCTAssertFalse(ImageInputSupport.needsVisualUnderstanding("Read the text in this image"))
        XCTAssertFalse(ImageInputSupport.needsVisualUnderstanding("What is a PDF?"))
        XCTAssertFalse(ImageInputSupport.needsVisualUnderstanding("What is your name?"))
    }

    func testConversationStorePreservesActiveRecordAndDraftAcrossSelection() async throws {
        let repository = InMemoryConversationRepository([])
        let store = ConversationStore(repository: repository, defaultModelID: "injected.model")
        XCTAssertEqual(store.active.modelID, "injected.model")
        let original = store.activeID
        store.draft = "Keep my draft"
        store.flush()
        store.create()
        let blank = store.activeID
        store.select(original)
        XCTAssertEqual(store.draft, "Keep my draft")
        XCTAssertFalse(store.items.contains { $0.id == blank })
        store.delete(original, replacementModelID: "replacement.model")
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.active.modelID, "replacement.model")
        XCTAssertEqual(store.active.id, store.activeID)
    }

    private func waitUntil(_ predicate: () async -> Bool) async {
        for _ in 0..<200 {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for controlled task")
    }
}

private enum ControlledFailure: Error { case expected }

private actor SuspendedImporter: DocumentImporter {
    private var pending: [CheckedContinuation<Attachment, Error>] = []
    var count: Int { pending.count }
    private(set) var completed = 0
    func prepare(_ attachment: Attachment) async throws -> Attachment {
        defer { completed += 1 }
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func remove(_ id: UUID) {}
    func fail(_ index: Int) { pending[index].resume(throwing: ControlledFailure.expected) }
    func finish(_ index: Int, item: Attachment) {
        var result = item
        result.readiness = .ready
        pending[index].resume(returning: result)
    }
}

private actor SuspendedMemoryCapture: MemoryCapture {
    private var pending: [CheckedContinuation<String, Never>] = []
    var count: Int { pending.count }
    private(set) var completed = 0
    func capture(_ request: ReplyRequest, onSaved: @Sendable (MemoryItem) async -> Void) async throws {
        let text = await withCheckedContinuation { pending.append($0) }
        // Intentionally ignores cancellation to exercise the receiver's identity guard.
        await onSaved(MemoryItem(text: text, origin: "test", state: .saved))
        completed += 1
    }
    func finish(_ index: Int, text: String) { pending[index].resume(returning: text) }
}
