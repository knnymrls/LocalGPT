import XCTest
import PDFKit
@testable import PumaWorkspace

final class WorkspaceTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testStaleSaveAndDeletionCannotResurrectChat() async throws {
        let url = try root().appendingPathComponent("workspace.sqlite")
        let db = try WorkspaceDatabase(url: url)
        let repo = LocalConversationRepository(database: db)
        var chat = Conversation(modelID: "test")
        chat.draft = "old"
        chat.revision = 1
        var newer = chat
        newer.draft = "new"
        newer.revision = 2
        try await repo.save(newer)
        try await repo.save(chat)
        let reopened = LocalConversationRepository(database: try WorkspaceDatabase(url: url))
        let loaded = try await reopened.all()
        XCTAssertEqual(loaded.first?.draft, "new")
        try await repo.delete(id: chat.id)
        try await repo.save(newer)
        let deleted = try await LocalConversationRepository(database: WorkspaceDatabase(url: url)).all()
        XCTAssertTrue(deleted.isEmpty)
    }

    func testInterruptedRepliesRecoverAsStoppedWithDraftIntact() async throws {
        let db = try WorkspaceDatabase(url: root().appendingPathComponent("workspace.sqlite"))
        let repo = LocalConversationRepository(database: db)
        var chat = Conversation(modelID: "test")
        chat.messages = [Message(role: .assistant, text: "partial", status: .streaming)]
        chat.draft = "my next thought"
        try await repo.save(chat)
        let loaded = try await repo.all()
        XCTAssertEqual(loaded.first?.messages.first?.status, .stopped)
        XCTAssertEqual(loaded.first?.draft, chat.draft)
    }

    func testSearchOnlyReturnsSelectedSourcesAndDeletionRevokesIndex() async throws {
        let db = try WorkspaceDatabase(url: root().appendingPathComponent("workspace.sqlite"))
        let first = UUID(), second = UUID()
        try await db.index([SourcePassage(sourceID: first, locator: "Page 1", text: "alpha private")], sourceID: first, fingerprint: "a")
        try await db.index([SourcePassage(sourceID: second, locator: "Page 2", text: "alpha other")], sourceID: second, fingerprint: "b")
        let selected = try await db.search("alpha", sourceIDs: [first])
        XCTAssertEqual(selected.map(\.sourceID), [first])
        try await db.delete(first, from: .attachments)
        let removed = try await db.search("alpha", sourceIDs: [first])
        XCTAssertTrue(removed.isEmpty)
        do {
            try await db.index([SourcePassage(sourceID: first, locator: "late", text: "alpha")], sourceID: first, fingerprint: "a")
            XCTFail("Deleted sources must not be reindexed by a late import")
        } catch is CancellationError {} catch { throw error }
    }

    func testMemoryReceiptFollowsCommitAndDuplicateContextHasNoNewReceipt() async throws {
        let db = try WorkspaceDatabase(url: root().appendingPathComponent("workspace.sqlite"))
        let repo = LocalMemoryRepository(database: db)
        let service = MemoryService(repository: repo, extract: { _ in
            [ExtractedMemory(text: "I prefer quiet venues.", evidence: "I prefer quiet venues.")]
        })
        let receipts = ReceiptRecorder()
        let request = ReplyRequest(conversationID: UUID(), prompt: "I prefer quiet venues.", history: [], modelID: "test", selectedSourceIDs: [], userMessageID: UUID())
        let receive: @Sendable (MemoryItem) async -> Void = { memory in
            let committed = (try? await repo.all())?.contains(where: { $0.id == memory.id }) ?? false
            await receipts.record(memory, committed: committed)
        }
        async let first: Void = service.capture(request, scope: RequestScope(), onSaved: receive)
        async let second: Void = service.capture(request, scope: RequestScope(), onSaved: receive)
        _ = try await (first, second)
        let saved = try await repo.all()
        let result = await receipts.snapshot()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.1 == true)
        XCTAssertEqual(saved.first?.messageID, request.userMessageID)
        XCTAssertEqual(saved.first?.sourceQuote, request.prompt)
    }

    func testFailedMemoryWriteNeverEmitsReceipt() async throws {
        let service = MemoryService(repository: FailingMemoryRepository(), extract: { _ in
            [ExtractedMemory(text: "I prefer quiet venues.", evidence: "I prefer quiet venues.")]
        })
        let receipts = ReceiptRecorder()
        let request = ReplyRequest(conversationID: UUID(), prompt: "I prefer quiet venues.", history: [], modelID: "test", selectedSourceIDs: [])
        do {
            try await service.capture(request, scope: RequestScope()) { await receipts.record($0, committed: false) }
            XCTFail("Expected a disk failure")
        } catch {}
        let saved = await receipts.snapshot()
        XCTAssertTrue(saved.isEmpty)
    }

    func testMemoryRequiresVerbatimEvidence() {
        XCTAssertFalse(MemoryExtractor.isGrounded(.init(text: "Lives in Paris", evidence: "I live in Paris"), in: "Where is Paris?"))
        XCTAssertEqual(MemoryExtractor.fingerprint("Quiet  Venues"), MemoryExtractor.fingerprint("quiet venues"))
    }

    func testDeletedConversationRejectsLateMemoryInsert() async throws {
        let db = try WorkspaceDatabase(url: root().appendingPathComponent("db.sqlite"))
        let chatID = UUID()
        try await db.delete(chatID, from: .conversations)
        var item = MemoryItem(text: "I prefer quiet venues", origin: "Test", state: .saved)
        item.conversationID = chatID
        item.fingerprint = MemoryExtractor.fingerprint(item.text)
        do {
            _ = try await db.insertMemoryIfNew(item)
            XCTFail("A deleted chat must not gain memories from canceled extraction")
        } catch is CancellationError {} catch { throw error }
    }

    func testRenderedDiagramCanBeReadWithOCRAndGeneratedTextIsSearchable() async throws {
        let root = try root()
        let db = try WorkspaceDatabase(url: root.appendingPathComponent("db.sqlite"))
        let repo = LocalAttachmentRepository(database: db)
        let files = WorkspaceFiles(root: root)
        let writer = ArtifactWriter(files: files, repository: repo, database: db)
        let diagram = try await writer.diagram(name: "Venue planning", steps: ["Inspect accessible entrances", "Confirm guest capacity"], conversationID: UUID(), scope: RequestScope())
        let importer = LocalDocumentImporter(files: files, database: db, repository: repo)
        let imported = try await importer.prepare(Attachment(name: "screenshot.png", kind: .image, readiness: .importing, fileURL: diagram.fileURL))
        XCTAssertTrue(imported.previewText.localizedCaseInsensitiveContains("accessible"))
        let matches = try await db.search("capacity", sourceIDs: [diagram.id])
        XCTAssertTrue(matches.contains { $0.text.contains("Confirm guest capacity") })
    }

    func testCSVQuotedNewlinesEscapesAndMalformedFields() throws {
        let table = try CSVTable.parse("name,amount\r\n\"A, B\",2\r\n\"A\"\"B\nC\",3\r\n")
        XCTAssertEqual(table.rows[1][0], "A, B")
        XCTAssertEqual(table.rows[2][0], "A\"B\nC")
        XCTAssertEqual(try table.summary(column: "amount", operation: "sum"), "5.0")
        XCTAssertThrowsError(try CSVTable.parse("a,b\n\"bad\"suffix,2"))
        XCTAssertThrowsError(try CSVTable.parse("a,b\n\"unterminated,2"))
        XCTAssertThrowsError(try CSVTable.parse("a,b\n1"))
    }

    func testPDFHasMultipleReadablePagesAndLastContent() async throws {
        let content = (1...400).map { "Line \($0): A readable report with details." }.joined(separator: "\n")
        let data = try ArtifactWriter.pdf(content)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("Line 400") == true)
    }

    func testGeneratedFilesStayInsideWorkspaceAndCancelPreventsWrite() async throws {
        let root = try root()
        let db = try WorkspaceDatabase(url: root.appendingPathComponent("db.sqlite"))
        let repo = LocalAttachmentRepository(database: db)
        let writer = ArtifactWriter(files: WorkspaceFiles(root: root), repository: repo, database: db)
        let file = try await writer.document(name: "../../example", format: "r", content: "print(1 + 1)", conversationID: UUID(), scope: RequestScope())
        let url = try XCTUnwrap(file.fileURL)
        XCTAssertTrue(url.path.hasPrefix(root.path + "/Files/"))
        XCTAssertEqual(url.lastPathComponent, "example.r")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "print(1 + 1)")
        let scope = RequestScope(); scope.cancel()
        do {
            _ = try await writer.document(name: "cancelled", format: "txt", content: "no", conversationID: UUID(), scope: scope)
            XCTFail("Cancelled generation cannot write a file")
        } catch is CancellationError {} catch { throw error }
        let saved = try await repo.all()
        XCTAssertEqual(saved.count, 1)
    }

    func testImportCopiesOriginalAndReusesContentCacheWithNewSourceID() async throws {
        let root = try root()
        let db = try WorkspaceDatabase(url: root.appendingPathComponent("db.sqlite"))
        let repo = LocalAttachmentRepository(database: db)
        let importer = LocalDocumentImporter(files: WorkspaceFiles(root: root), database: db, repository: repo)
        let source = root.appendingPathComponent("original.txt")
        try "The venue holds forty guests.".write(to: source, atomically: true, encoding: .utf8)
        let first = try await importer.prepare(Attachment(name: "venue.txt", kind: .text, readiness: .importing, fileURL: source))
        let second = try await importer.prepare(Attachment(name: "copy.txt", kind: .text, readiness: .importing, fileURL: source))
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(first.fileURL).path))
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        let matches = try await db.search("guests", sourceIDs: [second.id])
        XCTAssertEqual(matches.first?.sourceID, second.id)
        XCTAssertEqual(matches.first?.locator, "Text · passage 1")
    }
}

private actor ReceiptRecorder {
    var items: [(MemoryItem, Bool)] = []
    func record(_ item: MemoryItem, committed: Bool) { items.append((item, committed)) }
    func snapshot() -> [(MemoryItem, Bool)] { items }
}

private struct FailingMemoryRepository: MemoryRepository {
    func all() async throws -> [MemoryItem] { [] }
    func save(_ item: MemoryItem) async throws { throw WorkspaceError.message("Disk full") }
    func delete(id: UUID) async throws {}
}
