import XCTest
import PDFKit
import ImageIO
import FoundationModels
@testable import PumaWorkspace

final class WorkspaceTests: XCTestCase {
    func testConversationEchoDetectionAllowsRequestedCopiesAndGreetings() {
        func request(_ text: String) -> ReplyRequest {
            ReplyRequest(conversationID: UUID(), prompt: text, history: [], modelID: "test", selectedSourceIDs: [])
        }
        let remark = "I am just winding down after work."
        XCTAssertTrue(ConversationResponder.echoesUser(remark, request: request(remark)))
        XCTAssertFalse(ConversationResponder.echoesUser("Sounds like a long day. How was it?", request: request(remark)))
        XCTAssertFalse(ConversationResponder.echoesUser("Hello", request: request("Hello")))
        let explicit = "Repeat this sentence verbatim for me please."
        XCTAssertFalse(ConversationResponder.echoesUser(explicit, request: request(explicit)))
    }

    func testSeededConversationsPersistFilesAndRespectEditsAndDeletion() async throws {
        let directory = try root()
        let database = try WorkspaceDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
        let files = WorkspaceFiles(root: directory)
        let attachments = LocalAttachmentRepository(database: database, files: files)
        let conversations = LocalConversationRepository(database: database)
        let writer = ArtifactWriter(files: files, repository: attachments, database: database)
        let installer = ExampleConversationInstaller(database: database, writer: writer)
        let personal = Conversation(title: "My existing chat", messages: [Message(role: .user, text: "Keep this")], modelID: "test")
        try await conversations.save(personal)
        async let first: Void = installer.install()
        async let second: Void = installer.install()
        _ = try await (first, second)
        let seeded = try await conversations.all()
        XCTAssertEqual(seeded.count, 5)
        XCTAssertEqual(seeded.first(where: { $0.id == personal.id }), personal)
        for chat in seeded where chat.exampleID != nil {
            XCTAssertEqual(chat.messages.map(\.role), [.user, .assistant, .user, .assistant])
            XCTAssertTrue(chat.messages.allSatisfy { $0.savedMemoryIDs.isEmpty && $0.steps.isEmpty })
            XCTAssertTrue(chat.selectedSourceIDs.isEmpty)
            XCTAssertEqual(chat.exampleVersion, 2)
        }
        let outputs = try await attachments.all()
        XCTAssertEqual(outputs.count, 3)
        let csv = try XCTUnwrap(outputs.first { $0.fileURL?.pathExtension == "csv" }?.fileURL)
        let table = try CSVTable.parse(String(contentsOf: csv, encoding: .utf8))
        XCTAssertEqual(try table.summary(column: "amount", operation: "sum"), "80.0")
        let pdf = try XCTUnwrap(outputs.first { $0.kind == .pdf }?.fileURL)
        XCTAssertTrue(try XCTUnwrap(PDFDocument(url: pdf)?.string).contains("microphone"))
        let png = try XCTUnwrap(outputs.first { $0.fileURL?.pathExtension == "png" }?.fileURL)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let memories = try await database.readAll(.memories, as: MemoryItem.self)
        XCTAssertTrue(memories.isEmpty)

        var edited = try XCTUnwrap(seeded.first { $0.id == ExampleConversation.catalog[0].id })
        edited.title = "My plan"
        edited.draft = "Keep this draft"
        edited.revision += 1
        try await conversations.save(edited)
        let deletedID = ExampleConversation.catalog[1].id
        try await conversations.delete(id: deletedID)
        // A new installer models relaunch, after edits and a deleted seeded chat.
        try await ExampleConversationInstaller(database: database, writer: writer).install()
        let reopened = try await conversations.all()
        XCTAssertEqual(reopened.count, 4)
        XCTAssertEqual(reopened.first { $0.id == edited.id }, edited)
        XCTAssertFalse(reopened.contains { $0.id == deletedID })
        let reloadedOutputs = try await attachments.all()
        XCTAssertEqual(Set(reloadedOutputs.map(\.id)), Set(outputs.map(\.id)))

        // Existing installations have no exampleID key in their saved payloads.
        let data = try JSONEncoder().encode(personal)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertNil(decoded.exampleID)
    }

    func testLegacySeedUpgradeClearsOnlyOriginalInputsAndRepairsPNGThumbnail() async throws {
        let directory = try root()
        let database = try WorkspaceDatabase(url: directory.appendingPathComponent("workspace.sqlite"))
        let files = WorkspaceFiles(root: directory)
        let attachments = LocalAttachmentRepository(database: database, files: files)
        let conversations = LocalConversationRepository(database: database)
        let writer = ArtifactWriter(files: files, repository: attachments, database: database)
        try await ExampleConversationInstaller(database: database, writer: writer).install()
        let loaded = try await conversations.all()
        var chart = try XCTUnwrap(loaded.first { $0.id == ExampleConversation.catalog[3].id })
        let outputID = try XCTUnwrap(chart.messages.last?.documentIDs.first)
        let importedID = UUID()
        chart.exampleVersion = nil // Model the already installed version 1 chats.
        chart.selectedSourceIDs = [outputID, importedID]
        chart.title = "My chart"
        chart.draft = "Keep my draft"
        chart.revision += 1
        try await conversations.save(chart)
        let originalFiles = try await attachments.all()
        var png = try XCTUnwrap(originalFiles.first { $0.id == outputID })
        XCTAssertNotNil(png.thumbnail, "Newly generated PNGs include a preview immediately")
        png.thumbnail = nil // Model images generated before thumbnail support.
        try await attachments.save(png)

        try await ExampleConversationInstaller(database: database, writer: writer).install()
        let upgradedChats = try await conversations.all()
        let upgraded = try XCTUnwrap(upgradedChats.first { $0.id == chart.id })
        XCTAssertEqual(upgraded.selectedSourceIDs, [importedID])
        XCTAssertEqual(upgraded.title, "My chart")
        XCTAssertEqual(upgraded.draft, "Keep my draft")
        XCTAssertEqual(upgraded.messages, chart.messages)
        XCTAssertEqual(upgraded.exampleVersion, 2)
        let upgradedFiles = try await attachments.all()
        let image = try XCTUnwrap(upgradedFiles.first { $0.id == outputID })
        let thumbnail = try XCTUnwrap(image.thumbnail)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 360)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(image.fileURL).path))

        // Once migrated, an intentional later selection remains selected.
        var selectedAgain = upgraded
        selectedAgain.selectedSourceIDs.insert(outputID)
        selectedAgain.revision += 1
        try await conversations.save(selectedAgain)
        try await ExampleConversationInstaller(database: database, writer: writer).install()
        let again = try await conversations.all()
        XCTAssertEqual(again.first { $0.id == chart.id }?.selectedSourceIDs, [importedID, outputID])
    }

    func testConversationRepetitionIgnoresGreetingButAllowsChangedFactsAndRepeatRequests() {
        let reply = "I'm here to help you with whatever you need. What's on your mind?"
        XCTAssertTrue(ConversationResponder.repeats(ConversationResponder.normalized("Hey! " + reply), ConversationResponder.normalized(reply)))
        XCTAssertTrue(ConversationResponder.repeats(ConversationResponder.normalized("I'm just here to help you with whatever you need. What's on your mind?"), ConversationResponder.normalized(reply)))
        XCTAssertTrue(ConversationResponder.repeats(ConversationResponder.normalized("I'm just an AI assistant here to help you with whatever you need. What's on your mind?"), ConversationResponder.normalized(reply)))
        XCTAssertFalse(ConversationResponder.repeats("the room seats 140 guests and meets all of your requirements", "the room seats 120 guests and meets all of your requirements"))
        XCTAssertFalse(ConversationResponder.repeats("this room does not meet all of the requirements you specified earlier", "this room does meet all of the requirements you specified earlier"))
        let request = ReplyRequest(conversationID: UUID(), prompt: "Repeat that verbatim", history: [Message(role: .assistant, text: reply)], modelID: "test", selectedSourceIDs: [])
        XCTAssertTrue(ConversationResponder.repetitionCandidates(for: request).isEmpty)
    }

    func testConversationRestoresRolesAndExcludesCurrentAndFailedTurns() throws {
        let current = Message(role: .user, text: "What did I name it?")
        let request = ReplyRequest(conversationID: UUID(), prompt: current.text, history: [
            Message(role: .user, text: "An earlier failed request"),
            Message(role: .assistant, text: "A partial failed answer", status: .failed),
            Message(role: .user, text: "The ship is Juniper."),
            Message(role: .assistant, text: "Juniper it is."),
            current,
            Message(role: .assistant, text: "", status: .streaming)
        ], modelID: "test", selectedSourceIDs: [], userMessageID: current.id)
        let turns = ConversationContext.completedTurns(in: request)
        XCTAssertEqual(turns.count, 1)
        let pair = try XCTUnwrap(turns.first)
        guard case .prompt(let user) = pair[0], case .response(let assistant) = pair[1],
              case .text(let userText) = user.segments[0], case .text(let assistantText) = assistant.segments[0] else {
            return XCTFail("Stored speakers must become native model roles")
        }
        XCTAssertEqual(userText.content, "The ship is Juniper.")
        XCTAssertEqual(assistantText.content, "Juniper it is.")
    }

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
            [ExtractedMemory(text: "I prefer quiet venues.", evidence: "I prefer quiet venues.", kind: .lastingPreference)]
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
            [ExtractedMemory(text: "I prefer quiet venues.", evidence: "I prefer quiet venues.", kind: .lastingPreference)]
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

    func testMemoryPolicyKeepsTaskContextOutUnlessExplicitlyRequested() {
        for text in ["My event budget is 4200 dollars", "Now we need seating for 140 guests", "I prefer Riverside for this event", "I am visiting Boston tomorrow", "I just want to test this", "I just wanted to see if this works"] {
            XCTAssertFalse(MemoryPolicy.shouldSave(.init(text: text, evidence: text, kind: .enduringPersonalContext), in: text))
            XCTAssertFalse(MemoryPolicy.shouldSave(.init(text: text, evidence: text, kind: .explicitlyRequested), in: text))
        }
        let preference = "I prefer quiet venues"
        XCTAssertTrue(MemoryPolicy.shouldSave(.init(text: preference, evidence: preference, kind: .lastingPreference), in: preference))
        XCTAssertFalse(MemoryPolicy.shouldSave(.init(text: preference, evidence: preference, kind: .lastingPreference), in: preference + ". Do not remember this."))
        XCTAssertFalse(MemoryPolicy.shouldSave(.init(text: preference, evidence: preference, kind: .notMemory), in: preference))
        let budget = "my event budget is 4200 dollars"
        XCTAssertTrue(MemoryPolicy.shouldSave(.init(text: budget, evidence: budget, kind: .explicitlyRequested), in: "Remember that " + budget))
    }

    func testMemoryClausesSeparateIndependentFactsWithoutDroppingQualifications() {
        XCTAssertEqual(MemoryExtractor.clauses(in: "I prefer quiet venues and my event budget is 4200 dollars."), ["I prefer quiet venues", "my event budget is 4200 dollars."])
        let qualified = "I prefer quiet venues and outdoor seating only when it is warm."
        XCTAssertEqual(MemoryExtractor.clauses(in: qualified), [qualified])
    }

    func testExplicitMemoryCommandIsGroundedWithoutItsRequestPrefix() {
        let message = "Please remember that my event budget is 4200 dollars."
        let extracted = ExtractedMemory(text: "my event budget is 4200 dollars", evidence: message, kind: .explicitlyRequested)
        let quote = MemoryExtractor.factQuote(extracted)
        XCTAssertEqual(quote, "my event budget is 4200 dollars.")
        XCTAssertTrue(MemoryPolicy.shouldSave(.init(text: quote, evidence: quote, kind: .explicitlyRequested), in: message))
        XCTAssertFalse(MemoryPolicy.shouldSave(.init(text: quote, evidence: quote, kind: .explicitlyRequested), in: quote))
        XCTAssertFalse(MemoryPolicy.shouldSave(.init(text: quote, evidence: quote, kind: .explicitlyRequested), in: message + " Do not save this."))
    }

    func testMemoryRejectsQuestionsEvenWhenModelDropsPunctuation() {
        let message = "Now we need seating for 140 guests. Which venue qualifies, and what accessibility information still needs checking?"
        let fact = "Now we need seating for 140 guests"
        let question = "Which venue qualifies, and what accessibility information still needs checking"
        XCTAssertTrue(MemoryExtractor.isGrounded(.init(text: fact, evidence: fact), in: message))
        XCTAssertFalse(MemoryExtractor.isGrounded(.init(text: question, evidence: question), in: message))
        XCTAssertFalse(MemoryExtractor.isGrounded(.init(text: "We need seating", evidence: "We need seating"), in: "We need seating?"))
        let command = "Create a PDF named Venue Decision with our 140-guests requirement"
        XCTAssertFalse(MemoryExtractor.isGrounded(.init(text: command, evidence: command), in: command))
    }

    func testNumericComparisonComputesQualificationAndRejectsUngroundedValues() throws {
        let first = Citation(number: 1, sourceID: UUID(), locator: "Text", excerpt: "Harbor has seating for 120 guests.", range: 0..<33)
        let second = Citation(number: 2, sourceID: UUID(), locator: "Text", excerpt: "Riverside has seating for 160 guests.", range: 0..<36)
        let question = "We need seating for 140 guests. Which venue qualifies?"
        let valid = SourceNumericComparison(
            requirementQuote: "We need seating for 140 guests", threshold: 140, unit: "guests", relation: .atLeast,
            options: [
                .init(name: "Harbor", value: 120, citation: 1, quote: first.excerpt),
                .init(name: "Riverside", value: 160, citation: 2, quote: second.excerpt)
            ])
        var plan = try SourceNumericComparison.PartiallyGenerated(valid.generatedContent)
        let evidence = [first, second]
        let answer = SourceComparison.render(plan, question: question, evidence: evidence)
        XCTAssertTrue(answer?.contains("Harbor does not meet") == true)
        XCTAssertTrue(answer?.contains("Riverside meets") == true)
        plan.threshold = 120
        XCTAssertNil(SourceComparison.render(plan, question: question, evidence: evidence))
        plan.threshold = 140
        plan.options?[0].value = 180
        XCTAssertNil(SourceComparison.render(plan, question: question, evidence: evidence))
        var pricedSource = first
        pricedSource.excerpt = "Harbor has seating for 120 guests and costs $3200."
        plan.options?[0].value = 3200
        plan.options?[0].quote = pricedSource.excerpt
        XCTAssertNil(SourceComparison.render(plan, question: question, evidence: [pricedSource, second]), "A price must not be used as guest capacity")

        var invented = valid
        invented.requirementQuote = "atMost 140 guests"
        invented.relation = .atMost
        let candidates = SourceNumericPlan(comparisons: [valid, invented, valid])
        XCTAssertEqual(try SourceComparison.verifiedAnswers(candidates, question: question, evidence: evidence).count, 1)

        let names = [first.sourceID: "Harbor", second.sourceID: "Riverside"]
        let direct = try XCTUnwrap(SourceComparison.directRequirement(question: question, evidence: evidence, names: names))
        XCTAssertEqual(direct.threshold, 140)
        XCTAssertEqual(direct.options.map(\.value), [120, 160])
        XCTAssertEqual(SourceComparison.directRequirement(question: "Create a PDF with our 140-guests requirement.", evidence: evidence, names: names)?.threshold, 140)
        XCTAssertNil(SourceComparison.directRequirement(question: "We do not need 140 guests.", evidence: evidence, names: names))
        XCTAssertNil(SourceComparison.directRequirement(question: "We need a budget of 140 dollars.", evidence: evidence, names: names))
        XCTAssertNil(SourceComparison.directRequirement(question: question, evidence: [first, Citation(number: 2, sourceID: second.sourceID, locator: "Text", excerpt: "Riverside has 160 guests indoors and 200 guests outdoors.", range: 0..<54)], names: names))
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
        let repo = LocalAttachmentRepository(database: db, files: WorkspaceFiles(root: root))
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
        let repo = LocalAttachmentRepository(database: db, files: WorkspaceFiles(root: root))
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
        let repo = LocalAttachmentRepository(database: db, files: WorkspaceFiles(root: root))
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

    func testStoredFilesResolveAfterSandboxRelocationIncludingLegacyRecords() async throws {
        let root = try root()
        let db = try WorkspaceDatabase(url: root.appendingPathComponent("db.sqlite"))
        let oldFiles = WorkspaceFiles(root: root.appendingPathComponent("old-container"))
        let newFiles = WorkspaceFiles(root: root.appendingPathComponent("new-container"))
        let id = UUID()
        let content = Data("A durable original.".utf8)
        let oldURL = try oldFiles.write(content, id: id, name: "proposal.txt")
        let newURL = try newFiles.write(content, id: id, name: "proposal.txt")
        let item = Attachment(id: id, name: "proposal.txt", kind: .text, readiness: .ready, fileURL: oldURL)
        try await LocalAttachmentRepository(database: db, files: oldFiles).save(item)
        let stored = try await db.readAll(.attachments, as: Attachment.self)
        XCTAssertNil(stored.first?.fileURL, "Do not persist a sandbox's absolute URL")
        let relocated = LocalAttachmentRepository(database: db, files: newFiles)
        var reopened = try await relocated.all()
        XCTAssertEqual(reopened.first?.fileURL, newURL)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.first?.fileURL)), content)

        // Older installs used an absolute URL; loading upgrades it to the new root too.
        try await db.save(item, id: id, in: .attachments)
        reopened = try await relocated.all()
        XCTAssertEqual(reopened.first?.fileURL, newURL)
    }
}

private actor ReceiptRecorder {
    var items: [(MemoryItem, Bool)] = []
    func record(_ item: MemoryItem, committed: Bool) { items.append((item, committed)) }
    func snapshot() -> [(MemoryItem, Bool)] { items }
}

private struct FailingMemoryRepository: MemoryRepository {
    func insertIfNew(_ item: MemoryItem) async throws -> Bool { throw WorkspaceError.message("Disk full") }
    func all() async throws -> [MemoryItem] { [] }
    func save(_ item: MemoryItem) async throws { throw WorkspaceError.message("Disk full") }
    func delete(id: UUID) async throws {}
}
